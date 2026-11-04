import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function resolveCacheRoot(repository) {
  const repositoryPath = resolve(repository);
  const configPath = join(repositoryPath, '.cache', 'source-build-cache.json');
  if (existsSync(configPath)) {
    let configuration;
    try {
      configuration = JSON.parse(readFileSync(configPath, 'utf8'));
    } catch {
      throw new Error('Source cache configuration is invalid JSON: ' + configPath);
    }
    if (configuration?.schemaVersion !== 1) {
      throw new Error('Source cache configuration schemaVersion must be 1: ' + configPath);
    }
    if (typeof configuration.root !== 'string' || configuration.root.trim() === '' || !isAbsolute(configuration.root)) {
      throw new Error('Source cache configuration root must be a nonempty absolute path: ' + configPath);
    }
    return resolve(configuration.root);
  }

  let cursor = repositoryPath;
  while (true) {
    const candidate = join(cursor, 'SharedTemp');
    if (existsSync(candidate) && isDirectory(candidate)) return resolve(candidate, 'build-cache');
    const parent = dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }
  return join(repositoryPath, 'SharedTemp', 'build-cache');
}

export function resolveSourceBuildCachePaths(repository, environment = process.env) {
  const cacheRoot = resolveCacheRoot(repository);
  const firstNonEmpty = (...values) => values.find(value => typeof value === 'string' && value.trim() !== '');
  return {
    GoBuild: firstNonEmpty(environment.GOCACHE) ?? join(cacheRoot, 'go-build'),
    GoModules: firstNonEmpty(environment.GOMODCACHE) ?? join(cacheRoot, 'go-mod'),
    Npm: firstNonEmpty(environment.npm_config_cache, environment.NPM_CONFIG_CACHE) ?? join(cacheRoot, 'npm'),
  };
}

export function rebaseSourceBuildCachePath(cachePath, sourceDirectory, targetDirectory) {
  if (isAbsolute(cachePath)) return cachePath;
  const rebased = relative(resolve(targetDirectory), resolve(sourceDirectory, cachePath)) || '.';
  if (isAbsolute(rebased)) {
    throw new Error('A relative source cache must remain on the same filesystem root.');
  }
  return rebased;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  const [repository, cacheName, ...extra] = process.argv.slice(2);
  const validNames = ['GoBuild', 'GoModules', 'Npm'];
  if (!repository || !validNames.includes(cacheName) || extra.length !== 0) {
    process.stderr.write('Usage: node source-cache.mjs <repository> <GoBuild|GoModules|Npm>\n');
    process.exitCode = 2;
  } else {
    try {
      const paths = resolveSourceBuildCachePaths(repository);
      process.stdout.write(paths[cacheName] + '\n');
    } catch (error) {
      process.stderr.write(String(error?.message ?? error) + '\n');
      process.exitCode = 1;
    }
  }
}
