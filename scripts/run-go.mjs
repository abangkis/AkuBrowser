import { mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const workspaceRoot = fileURLToPath(new URL("../../", import.meta.url));
const sidecarRoot = fileURLToPath(new URL("../../AkuSidecar/", import.meta.url));
const cacheRoot = fileURLToPath(new URL("../../.go-cache/", import.meta.url));
const goCache = fileURLToPath(new URL("../../.go-cache/build/", import.meta.url));
const goModCache = fileURLToPath(new URL("../../.go-cache/mod/", import.meta.url));
const goTmpDir = fileURLToPath(new URL("../../.go-cache/tmp/", import.meta.url));

for (const directory of [cacheRoot, goCache, goModCache, goTmpDir]) {
  mkdirSync(directory, { recursive: true });
}

const result = spawnSync("go", process.argv.slice(2), {
  cwd: sidecarRoot,
  env: {
    ...process.env,
    GOCACHE: goCache,
    GOMODCACHE: goModCache,
    GOTMPDIR: goTmpDir,
    AKU_WORKSPACE_ROOT: workspaceRoot,
  },
  stdio: "inherit",
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
