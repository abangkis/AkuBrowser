import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixtureBase = join(repositoryRoot, '.cache', 'source-build-cache-tests');
mkdirSync(fixtureBase, { recursive: true });

function runFixture(t, { callerGo = false, exitCode = 0, beforeAllocation = false, failAllocation = false } = {}) {
  const bash = process.platform === 'win32'
    ? [process.env.AKUBROWSER_TEST_BASH, 'C:/Program Files/Git/bin/bash.exe', 'C:/Program Files (x86)/Git/bin/bash.exe'].filter(Boolean).find(existsSync)
    : 'bash';
  if (!bash) {
    t.skip('Bash is unavailable for the isolated packaging scratch regression');
    return;
  }
  const root = mkdtempSync(join(fixtureBase, 'macos-runtime-scratch-'));
  t.after(() => {
    assert.ok(resolve(root).startsWith(resolve(fixtureBase) + sep));
    rmSync(root, { recursive: true, force: true });
  });
  const browser = join(root, 'project with spaces');
  const ownedRoot = join(browser, '.cache', 'source-build-temp');
  const sibling = join(ownedRoot, 'akubrowser-macos-installer.ABCDEF');
  const callerTemp = join(root, 'caller temp');
  const callerGoRoot = join(root, 'caller go');
  const output = join(root, 'artifacts');
  const caches = ['go-build', 'go-mod', 'npm'].map(name => join(root, 'shared caches', name));
  const preserved = [sibling, callerTemp, callerGoRoot, ...caches].map(directory => {
    mkdirSync(directory, { recursive: true });
    const sentinel = join(directory, 'preserve.txt');
    writeFileSync(sentinel, 'preserve this caller or shared directory');
    return sentinel;
  });
  mkdirSync(output);
  const priorArtifact = join(output, 'prior.pkg');
  writeFileSync(priorArtifact, 'preserve prior output');
  const capture = join(root, 'paths.txt');
  const source = readFileSync(join(repositoryRoot, 'scripts', 'build-macos-runtime-installer.sh'), 'utf8').replaceAll('\r\n', '\n');
  const setupStart = source.indexOf('source_build_temp_root=');
  const setupEnd = source.indexOf('\nif [[ "$skip_validation"', setupStart);
  assert.ok(setupStart >= 0 && setupEnd > setupStart);
  const allocation = source.split('\n').filter(line => line.startsWith('build_root="$(mktemp -d '));
  assert.equal(allocation.length, 1, 'the fixture must execute the production packaging allocation');
  const failMktemp = failAllocation ? [
    'mktemp() {',
    '  case "${2:-}" in',
    '    */akubrowser-macos-installer.XXXXXX) return 47 ;;',
    '    *) command mktemp "$@" ;;',
    '  esac',
    '}',
  ].join('\n') : '';
  const command = [
    'set -euo pipefail',
    'browser_root="$1"; fixture_root="$2"; fixture_capture="$3"',
    'go_cache="$fixture_root/shared caches/go-build"',
    'go_mod_cache="$fixture_root/shared caches/go-mod"',
    'npm_cache="$fixture_root/shared caches/npm"',
    failMktemp,
    source.slice(setupStart, setupEnd),
    'printf "%s\\n" "$source_build_temp_root" "$go_temp_dir" > "$fixture_capture"',
    beforeAllocation ? 'exit 29' : '',
    allocation[0],
    'printf "%s\\n" "$build_root" >> "$fixture_capture"',
    'mkdir -p "$build_root/payload"',
    'printf "temporary payload" > "$build_root/payload/temporary.txt"',
    'printf "generated output" > "$fixture_root/artifacts/generated.pkg"',
    `exit ${exitCode}`,
  ].join('\n');
  const environment = Object.fromEntries(Object.entries(process.env).filter(([key]) => !['gotmpdir', 'tmpdir', 'build_root'].includes(key.toLowerCase())));
  Object.assign(environment, { BASH_ENV: '', ENV: '', TMPDIR: toBashPath(callerTemp), build_root: toBashPath(callerTemp) });
  if (callerGo) environment.GOTMPDIR = toBashPath(callerGoRoot);
  const result = spawnSync(bash, ['--noprofile', '--norc', '-c', command, '--',
    toBashPath(browser), toBashPath(root), toBashPath(capture)], {
    cwd: root, env: environment, encoding: 'utf8', timeout: 15000,
  });
  assert.ifError(result.error);
  assert.ok(existsSync(capture), result.stderr);
  const paths = readFileSync(capture, 'utf8').trim().split('\n').map(fromBashPath);
  return { result, paths, ownedRoot, sibling, callerGoRoot, callerGo, output, priorArtifact, preserved };
}

function assertRetained(f) {
  for (const file of f.preserved) assert.equal(readFileSync(file, 'utf8'), 'preserve this caller or shared directory');
  assert.equal(readFileSync(f.priorArtifact, 'utf8'), 'preserve prior output');
  assert.equal(f.paths[0], f.ownedRoot);
  if (f.callerGo) assert.equal(f.paths[1], f.callerGoRoot);
  else {
    assert.ok(f.paths[1].startsWith(f.ownedRoot + sep));
    assert.equal(existsSync(f.paths[1]), false, 'owned Go scratch must be cleaned');
  }
  assert.deepEqual(readdirSync(f.ownedRoot), [basename(f.sibling)], 'cleanup must retain the parent and pre-existing sibling only');
}

for (const callerGo of [false, true]) {
  for (const exitCode of [0, 31]) {
    test(`macOS packaging scratch is project-local and cleaned on exit ${exitCode} (${callerGo ? 'caller' : 'owned'} Go scratch)`, (t) => {
      const f = runFixture(t, { callerGo, exitCode });
      if (!f) return;
      assert.equal(f.result.status, exitCode, f.result.stderr);
      assert.equal(f.paths.length, 3);
      assert.ok(f.paths[2].startsWith(f.ownedRoot + sep), 'packaging scratch must be created under the project-local temp root');
      assert.match(basename(f.paths[2]), /^akubrowser-macos-installer\./);
      assert.notEqual(f.paths[2], f.paths[1], 'packaging and Go scratch must have independent ownership');
      assert.equal(existsSync(f.paths[2]), false, 'packaging scratch must be cleaned after success or failure');
      assert.equal(readFileSync(join(f.output, 'generated.pkg'), 'utf8'), 'generated output');
      assertRetained(f);
    });
  }
}

test('macOS validation failure before packaging allocation preserves caller directories and clears owned Go scratch', (t) => {
  const f = runFixture(t, { beforeAllocation: true });
  if (!f) return;
  assert.equal(f.result.status, 29, f.result.stderr);
  assert.equal(f.paths.length, 2);
  assert.equal(existsSync(join(f.output, 'generated.pkg')), false);
  assertRetained(f);
});

test('macOS packaging mktemp failure retains its exit code and never claims the inherited build_root', (t) => {
  const f = runFixture(t, { failAllocation: true });
  if (!f) return;
  assert.equal(f.result.status, 47, f.result.stderr);
  assert.equal(f.paths.length, 2);
  assert.equal(existsSync(join(f.output, 'generated.pkg')), false);
  assertRetained(f);
});

function toBashPath(value) {
  const absolute = resolve(value);
  if (process.platform !== 'win32') return absolute;
  const match = absolute.replaceAll('\\', '/').match(/^([A-Za-z]):(\/.*)$/);
  assert.ok(match);
  return '/' + match[1].toLowerCase() + match[2];
}

function fromBashPath(value) {
  if (process.platform !== 'win32') return resolve(value);
  const match = value.match(/^\/([A-Za-z])\/(.*)$/);
  return match ? resolve(`${match[1].toUpperCase()}:/${match[2]}`) : resolve(value);
}
