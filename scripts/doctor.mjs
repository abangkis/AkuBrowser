import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.dirname(projectRoot);
const browserPackage = readJson(path.join(projectRoot, "package.json"));
const bridgePackage = readJson(path.join(workspaceRoot, "AkuBridge", "package.json"));
const bridgeManifest = readJson(path.join(workspaceRoot, "AkuBridge", "manifest.json"));
const sidecarPackage = readJson(path.join(workspaceRoot, "AkuSidecar", "package.json"));
const checks = [];

add("component_identities", [
  browserPackage.version,
  bridgePackage.version,
  sidecarPackage.version,
].every((version) => /^\d+\.\d+\.\d+$/.test(version)) &&
  bridgePackage.version === bridgeManifest.version, {
  AkuBrowser: browserPackage.version,
  AkuBridge: bridgePackage.version,
  AkuBridgeManifest: bridgeManifest.version,
  AkuSidecar: sidecarPackage.version,
  versionPolicy: "independent_component_versions",
});

const health = await safeFetch("http://127.0.0.1:47821/api/health");
add("sidecar_health", health.ok && health.body?.status === "ok", health.body ?? health.error);
const database = await safeFetch("http://127.0.0.1:47821/api/operations/database/health");
add("database_integrity", database.ok && database.body?.database?.status === "healthy", database.body ?? database.error);
const bridge = await safeFetch("http://127.0.0.1:47821/api/operations/bridge/health");
const bridgeStatus = bridge.body?.bridge?.status;
add("bridge_runtime", bridge.ok && bridgeStatus === "healthy", bridge.body ?? bridge.error, {
  warning: bridge.ok && ["unavailable", "degraded"].includes(bridgeStatus),
});
add("bridge_runtime_revision", bridge.ok &&
  bridge.body?.bridge?.runtime?.heartbeat?.runtimeRevision === bridgePackage.akuRuntimeRevision,
  {
    expected: bridgePackage.akuRuntimeRevision,
    observed: bridge.body?.bridge?.runtime?.heartbeat?.runtimeRevision ?? null,
  }, {
    warning: bridge.ok && bridgeStatus === "unavailable",
  });
add(
  "bridge_compatibility",
  bridge.ok && bridge.body?.bridge?.compatibility?.compatible === true,
  bridge.body?.bridge?.compatibility ?? bridge.error,
  { warning: bridge.ok && bridgeStatus === "unavailable" },
);

const report = {
  version: 2,
  status: checks.every((entry) => entry.passed) ? "healthy" : "degraded",
  checkedAt: new Date().toISOString(),
  checks,
  manualChecks: [
    "After the one-time unpacked-extension bootstrap, use AkuSupervisor bridge validate/reload after AkuBridge source changes.",
    "Confirm signed-in canonical X and LinkedIn feed tabs when fail-fast behavior is desired.",
  ],
  mutationsPerformed: false,
};
console.log(JSON.stringify(report, null, 2));
if (checks.some((entry) => !entry.passed && entry.severity === "error")) process.exitCode = 1;

function add(id, passed, detail, { warning = false } = {}) {
  checks.push({ id, passed: passed === true, severity: passed ? "none" : warning ? "warning" : "error", detail });
}

async function safeFetch(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(3_000) });
    const body = await response.json();
    return { ok: response.ok, body };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}
