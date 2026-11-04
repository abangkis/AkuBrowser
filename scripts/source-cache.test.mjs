import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { resolveSourceBuildCachePaths } from './source-cache.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const repositoryRoot = resolve(dirname(scriptPath), '..');
const fixtureBase = join(repositoryRoot, '.cache', 'source-build-cache-tests');
mkdirSync(fixtureBase, { recursive: true });

function createFixture(t) {
  const root = mkdtempSync(join(fixtureBase, 'node-resolver-'));
  const ancestor = join(root, 'ancestor');
  const repository = join(ancestor, 'project', 'repo');
  mkdirSync(join(ancestor, 'SharedTemp'), { recursive: true });
  mkdirSync(repository, { recursive: true });
  t.after(() => {
    const base = resolve(fixtureBase) + sep;
    const target = resolve(root);
    assert.ok(target.startsWith(base), 'fixture cleanup must remain inside its owned test root');
    rmSync(target, { recursive: true, force: true });
  });
  return { root, ancestor, repository };
}

test('uses the nearest existing ancestor SharedTemp for defaults', (t) => {
  const fixture = createFixture(t);
  const paths = resolveSourceBuildCachePaths(fixture.repository, {});
  const expectedRoot = join(fixture.ancestor, 'SharedTemp', 'build-cache');
  assert.equal(paths.GoBuild, join(expectedRoot, 'go-build'));
  assert.equal(paths.GoModules, join(expectedRoot, 'go-mod'));
  assert.equal(paths.Npm, join(expectedRoot, 'npm'));
});

test('uses local configuration, then honors process cache overrides', (t) => {
  const fixture = createFixture(t);
  const configuredRoot = join(fixture.root, 'configured-cache');
  const configDirectory = join(fixture.repository, '.cache');
  mkdirSync(configDirectory, { recursive: true });
  writeFileSync(join(configDirectory, 'source-build-cache.json'), JSON.stringify({ schemaVersion: 1, root: configuredRoot }));
  const configured = resolveSourceBuildCachePaths(fixture.repository, {});
  assert.equal(configured.GoBuild, join(configuredRoot, 'go-build'));
  assert.equal(configured.GoModules, join(configuredRoot, 'go-mod'));
  assert.equal(configured.Npm, join(configuredRoot, 'npm'));

  const overridden = resolveSourceBuildCachePaths(fixture.repository, {
    GOCACHE: join(fixture.root, 'override-go-build'),
    GOMODCACHE: join(fixture.root, 'override-go-mod'),
    npm_config_cache: join(fixture.root, 'override-npm'),
  });
  assert.equal(overridden.GoBuild, join(fixture.root, 'override-go-build'));
  assert.equal(overridden.GoModules, join(fixture.root, 'override-go-mod'));
  assert.equal(overridden.Npm, join(fixture.root, 'override-npm'));
  assert.equal(resolveSourceBuildCachePaths(fixture.repository, {
    npm_config_cache: 'relative lower', NPM_CONFIG_CACHE: 'relative upper',
  }).Npm, 'relative lower');
  assert.equal(resolveSourceBuildCachePaths(fixture.repository, {
    npm_config_cache: '', NPM_CONFIG_CACHE: 'relative upper',
  }).Npm, 'relative upper');
});

test('CLI prints a selected path and rejects malformed local configuration', (t) => {
  const fixture = createFixture(t);
  const environment = { ...process.env, GOCACHE: '', GOMODCACHE: '', npm_config_cache: '' };
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('./source-cache.mjs', import.meta.url)), fixture.repository, 'GoBuild'], {
    encoding: 'utf8',
    env: environment,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), join(fixture.ancestor, 'SharedTemp', 'build-cache', 'go-build'));

  const configDirectory = join(fixture.repository, '.cache');
  mkdirSync(configDirectory, { recursive: true });
  writeFileSync(join(configDirectory, 'source-build-cache.json'), JSON.stringify({ schemaVersion: 2, root: fixture.root }));
  assert.throws(() => resolveSourceBuildCachePaths(fixture.repository, {}), /schemaVersion must be 1/);
});
test('macOS Step 3B cleanup preserves existing staging after failure', (t) => {
  const fixture = createFixture(t);
  const bashPath = process.platform === 'win32'
    ? [process.env.AKUBROWSER_TEST_BASH, 'C:/Program Files/Git/bin/bash.exe', 'C:/Program Files (x86)/Git/bin/bash.exe'].filter(Boolean).find(existsSync)
    : 'bash';
  if (!bashPath) {
    t.skip('Bash is unavailable for the isolated staging cleanup regression');
    return;
  }

  const scriptPath = join(repositoryRoot, 'scripts', 'build-macos-3b-acceptance-kit.sh');
  const script = readFileSync(scriptPath, 'utf8');
  const cleanupFunction = script.match(/cleanup_source_build_temp\(\) \{[\s\S]*?^\}/m)?.[0];
  assert.ok(cleanupFunction, 'production cleanup function must be present for the regression fixture');
  assert.match(cleanupFunction, /owns_building_root/);
  assert.match(script, /mv "\$building_root" "\$output_root"\r?\n\s*owns_building_root=0/,
    'a successful promotion must release ownership before exit cleanup');


  const guardIndex = script.indexOf('[[ ! -e "$building_root" ]]');
  const createIndex = script.indexOf('mkdir "$building_root"', guardIndex);
  const ownershipIndex = script.indexOf('owns_building_root=1', createIndex);
  assert.ok(guardIndex >= 0 && createIndex > guardIndex && ownershipIndex > createIndex,
    'the builder must claim staging only after an exclusive mkdir succeeds');
  const initializationIndex = script.indexOf('owns_building_root=0');
  assert.ok(initializationIndex >= 0 && initializationIndex < guardIndex,
    'the cleanup owner flag must start false before the existing-staging guard');

  const runCleanup = (stagingPath, ownsStaging) => spawnSync(bashPath, [
    '-c',
    [
      'set -euo pipefail',
      'building_root="$1"',
      'source_build_temp_root="$2"',
      'owns_building_root="$3"',
      'go_temp_dir=""',
      'owns_go_temp_dir=0',
      cleanupFunction,
      'trap cleanup_source_build_temp EXIT',
      'exit 1',
    ].join('\n'),
    '--',
    toBashPath(stagingPath),
    toBashPath(join(fixture.root, 'go-temp')),
    String(ownsStaging),
  ], { encoding: 'utf8' });

  const existingStaging = join(fixture.root, 'pre-existing.building');
  mkdirSync(existingStaging);
  const evidence = join(existingStaging, 'preserve.txt');
  writeFileSync(evidence, 'preserve this prior staging');
  const failedExisting = runCleanup(existingStaging, 0);
  assert.equal(failedExisting.status, 1, failedExisting.stderr);
  assert.equal(readFileSync(evidence, 'utf8'), 'preserve this prior staging');

  const ownedStaging = join(fixture.root, 'owned.building');
  mkdirSync(ownedStaging);
  writeFileSync(join(ownedStaging, 'temporary.txt'), 'owned by this run');
  const failedOwned = runCleanup(ownedStaging, 1);
  assert.equal(failedOwned.status, 1, failedOwned.stderr);
  assert.equal(existsSync(ownedStaging), false, 'a failed run should clean its own staging');
});

test('macOS runtime installer preserves relative npm cache identity after changing directories', (t) => {
  const fixture = createFixture(t);
  const bashPath = process.platform === 'win32'
    ? [process.env.AKUBROWSER_TEST_BASH, 'C:/Program Files/Git/bin/bash.exe', 'C:/Program Files (x86)/Git/bin/bash.exe'].filter(Boolean).find(existsSync)
    : 'bash';
  if (!bashPath) {
    t.skip('Bash is unavailable for the isolated npm cache regression');
    return;
  }
  const wrapper = readFileSync(join(repositoryRoot, 'scripts', 'build-macos-runtime-installer.sh'), 'utf8');
  const cacheStart = wrapper.indexOf('source_cache_helper=');
  const cacheEnd = wrapper.indexOf('source_build_temp_root=', cacheStart);
  assert.ok(cacheStart >= 0 && cacheEnd > cacheStart, 'production cache setup must be present');
  const npmCommand = wrapper.match(/^\s*\(cd "\$bridge_root" && npm_config_cache="[^"\n]+" npm run check\)\s*$/m)?.[0];
  assert.ok(npmCommand, 'the fixture must execute the production npm invocation');
  const bridgeRoot = join(fixture.repository, 'bridge package');
  mkdirSync(bridgeRoot);
  for (const cache of ['relative cache', relative(fixture.root, bridgeRoot), join(fixture.root, 'absolute cache')]) {
    const environment = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== 'npm_config_cache'));
    environment.npm_config_cache = cache;
    const result = spawnSync(bashPath, ['-c', [
      'set -euo pipefail',
      'browser_root="$1"',
      'bridge_root="$2"',
      wrapper.slice(cacheStart, cacheEnd),
      'npm() { node -e \'console.log(JSON.stringify({ cache: process.env.npm_config_cache, cwd: process.cwd(), args: process.argv.slice(1) }))\' "$@"; }',
      npmCommand,
    ].join('\n'), '--', toBashPath(repositoryRoot), toBashPath(bridgeRoot)], {
      cwd: fixture.root, env: environment, encoding: 'utf8', timeout: 15000,
    });
    assert.equal(result.status, 0, result.stderr);
    const captured = JSON.parse(result.stdout);
    assert.deepEqual(captured.args, ['run', 'check']);
    assert.equal(captured.cwd, bridgeRoot);
    assert.equal(isAbsolute(captured.cache), isAbsolute(cache), 'a relative npm override must remain relative');
    assert.equal(resolve(captured.cwd, captured.cache), resolve(fixture.root, cache),
      'npm must use the cache selected before the package cwd change');
    if (isAbsolute(cache)) assert.equal(captured.cache, cache, 'absolute overrides must remain unchanged');
  }
});

function toBashPath(value) {
  const absolutePath = resolve(value);
  if (process.platform !== 'win32') return absolutePath;
  const normalizedPath = absolutePath.replaceAll('\\', '/');
  const drivePath = normalizedPath.match(/^([A-Za-z]):(\/.*)$/);
  assert.ok(drivePath, 'Windows fixture paths must have a drive prefix for Git Bash');
  return '/' + drivePath[1].toLowerCase() + drivePath[2];
}
