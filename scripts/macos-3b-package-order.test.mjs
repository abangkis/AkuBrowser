import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixtureBase = join(repositoryRoot, '.cache', 'source-build-cache-tests');
mkdirSync(fixtureBase, { recursive: true });
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function fixture(t, { inherited = false, existing = false, invalidProfile = false } = {}) {
  const bash = process.platform === 'win32'
    ? [process.env.AKUBROWSER_TEST_BASH, 'C:/Program Files/Git/bin/bash.exe', 'C:/Program Files (x86)/Git/bin/bash.exe'].filter(Boolean).find(existsSync)
    : 'bash';
  if (!bash) {
    t.skip('Bash is unavailable for the isolated Step 3B package regression');
    return;
  }
  const root = mkdtempSync(join(fixtureBase, 'step3b-package-'));
  t.after(() => {
    assert.ok(resolve(root).startsWith(resolve(fixtureBase) + sep));
    rmSync(root, { recursive: true, force: true });
  });
  const sourceRoot = join(root, 'source package');
  const decoy = join(root, 'caller package');
  const output = join(root, 'generated kit');
  const staging = output + '.building';
  const originals = {
    'manifest.json': JSON.stringify({ manifest_version: 3, name: 'fixture', version: '1.0.0', key: 'source-key' }) + '\n',
    'bridge-deployment.js': 'export const BRIDGE_DEPLOYMENT = Object.freeze({ mode: "source" });\n',
    'features/item.js': 'export const fixture = true;\n',
  };
  for (const base of [sourceRoot, decoy]) {
    for (const [name, bytes] of Object.entries(originals)) {
      mkdirSync(dirname(join(base, name)), { recursive: true });
      writeFileSync(join(base, name), bytes);
    }
  }
  const profile = JSON.parse(readFileSync(join(repositoryRoot, 'config', 'bridge-identities.json'), 'utf8')).profiles.acceptance;
  const registryPath = join(root, 'identity.json');
  writeFileSync(registryPath, JSON.stringify({ schemaVersion: 2, profiles: invalidProfile ? {} : { acceptance: profile } }));
  const verificationPath = join(root, 'verification.json');
  writeFileSync(verificationPath, JSON.stringify({ files: Object.entries(originals).map(([path, bytes]) => ({ path, sha256: sha256(bytes) })) }));
  const tracePath = join(root, 'trace.txt');
  writeFileSync(tracePath, '');
  if (existing) {
    mkdirSync(staging);
    writeFileSync(join(staging, 'preserve.txt'), 'prior staging');
  }

  const script = readFileSync(join(repositoryRoot, 'scripts', 'build-macos-3b-acceptance-kit.sh'), 'utf8').replaceAll('\r\n', '\n');
  const tupleStart = script.indexOf('node --input-type=module - "$final_kit_manifest" "$browser_root" "$bridge_root" "$sidecar_root"');
  const tupleEnd = script.indexOf('\nNODE\n', tupleStart);
  const packageEnd = script.indexOf('\nbridge_zip=', tupleEnd);
  assert.ok(tupleStart >= 0 && tupleEnd > tupleStart && packageEnd > tupleEnd);
  const packageCommands = script.slice(tupleEnd + '\nNODE\n'.length, packageEnd);
  const cleanup = script.match(/cleanup_source_build_temp\(\) \{[\s\S]*?^\}/m)?.[0];
  assert.ok(cleanup);
  const inspectPackage = [
    'node --input-type=module - "$unpacked_root" "$package_fingerprint_json" <<\'INSPECT\'',
    'import fs from "node:fs"; import path from "node:path";',
    'const [root, fingerprint] = process.argv.slice(2); const parsed = JSON.parse(fingerprint);',
    'const files = Object.fromEntries(parsed.files.map(({path: name}) => [name, fs.readFileSync(path.join(root, name), "utf8")]));',
    'console.log(JSON.stringify({ files, fingerprint: parsed }));',
    'INSPECT',
  ].join('\n');
  const command = [
    'set -euo pipefail',
    'browser_root="$1"; bridge_root="$2"; identity_registry="$3"; output_root="$4"',
    'fixture_trace="$5"; fixture_verification="$6"; fixture_windows="$7"',
    'sidecar_version=fixture; bridge_version=fixture',
    'building_root=""; owns_building_root=0; go_temp_dir=""; owns_go_temp_dir=0',
    'source_build_temp_root="$browser_root/.cache/source-build-temp"',
    inherited ? ':' : 'unset unpacked_root',
    'die() { printf "error: %s\\n" "$*" >&2; exit 1; }',
    cleanup,
    'trap cleanup_source_build_temp EXIT',
    'node() {',
    '  if [[ "$1" = "$bridge_root/scripts/verify-extension-package.mjs" ]]; then',
    '    printf "verify\\n" >> "$fixture_trace"; printf "%s\\n" "$(<"$fixture_verification")"; return',
    '  fi',
    // Windows Node prints drive paths; preserve the fixture's canonical Bash path
    // for this platform adapter only. The production containment guard still runs.
    '  if [[ "$fixture_windows" = 1 && "$1" = --input-type=module && "${2:-}" = -e && "${3:-}" = \'import path from "node:path"; console.log(path.resolve(process.argv[1]))\' ]]; then',
    '    printf "%s\\n" "$4"; return',
    '  fi',
    '  if [[ "$1" = "$browser_root/scripts/project-bridge-package-identity.mjs" ]]; then',
    '    local copied=0; [[ ! -f "$3/manifest.json" ]] || copied=1',
    '    printf "project|%s|%s|%s\\n" "$3" "$owns_building_root" "$copied" >> "$fixture_trace"',
    '  elif [[ "$1" = "$browser_root/scripts/fingerprint-extension-directory.mjs" ]]; then',
    '    printf "fingerprint\\n" >> "$fixture_trace"',
    '  fi',
    '  command node "$@"',
    '}',
    packageCommands,
    inspectPackage,
  ].join('\n');
  const environment = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== 'unpacked_root'));
  Object.assign(environment, { BASH_ENV: '', ENV: '' });
  if (inherited) environment.unpacked_root = toBashPath(decoy);
  const result = spawnSync(bash, ['--noprofile', '--norc', '-c', command, '--',
    toBashPath(repositoryRoot), toBashPath(sourceRoot), toBashPath(registryPath), toBashPath(output),
    toBashPath(tracePath), toBashPath(verificationPath), process.platform === 'win32' ? '1' : '0'], {
    cwd: root, env: environment, encoding: 'utf8', timeout: 20000,
  });
  assert.ifError(result.error);
  return { result, profile, sourceRoot, decoy, staging, originals,
    trace: readFileSync(tracePath, 'utf8').trim().split('\n').filter(Boolean) };
}

function assertInputsPreserved(f) {
  for (const base of [f.sourceRoot, f.decoy]) {
    for (const [name, bytes] of Object.entries(f.originals)) assert.equal(readFileSync(join(base, name), 'utf8'), bytes);
  }
}

for (const inherited of [false, true]) {
  test(`Step 3B projects copied bytes before fingerprinting (${inherited ? 'inherited' : 'unset'} unpacked_root)`, (t) => {
    const f = fixture(t, { inherited });
    if (!f) return;
    assert.equal(f.result.status, 0, f.result.stderr);
    const captured = JSON.parse(f.result.stdout);
    assert.equal(JSON.parse(captured.files['manifest.json']).key, f.profile.publicKey);
    const deploymentText = captured.files['bridge-deployment.js'];
    const deployment = JSON.parse(deploymentText.slice(deploymentText.indexOf('Object.freeze(') + 'Object.freeze('.length, deploymentText.lastIndexOf(');')));
    assert.equal(deployment.mode, 'acceptance');
    assert.equal(deployment.identityProfile, 'acceptance');
    assert.equal(deployment.runtimeLifecycle, f.profile.runtimeLifecycle);
    const expectedFiles = Object.entries(captured.files).sort(([a], [b]) => a.localeCompare(b)).map(([path, bytes]) => ({ path, sha256: sha256(bytes) }));
    assert.deepEqual(captured.fingerprint.files, expectedFiles);
    assert.equal(captured.fingerprint.fingerprint, sha256(JSON.stringify(expectedFiles)));
    assert.equal(f.trace[0], 'verify');
    assert.equal(f.trace[1], `project|${toBashPath(join(f.staging, 'acceptance', 'AkuBridge-fixture-prestore-unpacked'))}|1|1`);
    assert.deepEqual(f.trace.slice(2), ['fingerprint']);
    assert.equal(existsSync(f.staging), false, 'EXIT cleanup must remove only the owned fixture staging');
    assertInputsPreserved(f);
  });
}

test('Step 3B preserves prior staging and ignores an inherited target before claiming ownership', (t) => {
  const f = fixture(t, { inherited: true, existing: true });
  if (!f) return;
  assert.equal(f.result.status, 1, f.result.stderr);
  assert.match(f.result.stderr, /prior incomplete Step 3B staging exists/);
  assert.equal(readFileSync(join(f.staging, 'preserve.txt'), 'utf8'), 'prior staging');
  assert.deepEqual(f.trace, []);
  assertInputsPreserved(f);
});

test('Step 3B projection failure cleans owned staging without touching source or caller target', (t) => {
  const f = fixture(t, { invalidProfile: true });
  if (!f) return;
  assert.equal(f.result.status, 1, f.result.stderr);
  assert.match(f.result.stderr, /unsupported or missing Bridge identity profile/);
  assert.equal(f.trace[0], 'verify');
  assert.match(f.trace[1], /^project\|.*\|1\|1$/);
  assert.equal(f.trace.length, 2);
  assert.equal(existsSync(f.staging), false, 'projection failure must clean its owned staging');
  assertInputsPreserved(f);
});

function toBashPath(value) {
  const absolute = resolve(value);
  if (process.platform !== 'win32') return absolute;
  const match = absolute.replaceAll('\\', '/').match(/^([A-Za-z]):(\/.*)$/);
  assert.ok(match);
  return '/' + match[1].toLowerCase() + match[2];
}
