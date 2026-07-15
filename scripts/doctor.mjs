import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.dirname(projectRoot);
const browserPackage = readJson(path.join(projectRoot, "package.json"));
const bridgePackage = readJson(path.join(workspaceRoot, "AkuBridge", "package.json"));
const bridgeManifest = readJson(path.join(workspaceRoot, "AkuBridge", "manifest.json"));
const sidecarDomain = fs.readFileSync(path.join(workspaceRoot, "AkuSidecar", "internal", "domain", "types.go"), "utf8");
const sidecarVersion = sidecarDomain.match(/ApplicationVersion\s*=\s*"([^"]+)"/)?.[1] ?? null;
const checks = [];

add("component_identities",
  /^\d+\.\d+\.\d+$/.test(browserPackage.version) &&
  bridgePackage.version === bridgeManifest.version &&
  sidecarVersion === "1.0.0-dev.4", {
    AkuBrowser: browserPackage.version,
    AkuBridge: bridgePackage.version,
    AkuBridgeManifest: bridgeManifest.version,
    AkuSidecar: sidecarVersion,
    versionPolicy: "independent_component_versions",
  });

const health = await safeFetch("http://127.0.0.1:47821/api/health");
add("sidecar_health",
  health.ok && health.body?.status === "ok" && health.body?.runtime === "go" &&
  health.body?.version === sidecarVersion && health.body?.bridgeContractVersion === "aku-browser.bridge.v2" &&
  health.body?.provider === "codex-app-server",
  health.body ?? health.error);
add("database_integrity", health.ok && health.body?.database?.status === "healthy", health.body?.database ?? health.error);

const bridge = await safeFetch("http://127.0.0.1:47821/api/bridge/health");
const state = bridge.body?.bridge?.state;
add("bridge_runtime", bridge.ok && state === "healthy", bridge.body ?? bridge.error, {
  warning: bridge.ok && state === "reconnecting",
});
add("bridge_runtime_revision", bridge.ok &&
  bridge.body?.bridge?.actual?.runtimeRevision === bridgePackage.akuRuntimeRevision, {
    expected: bridgePackage.akuRuntimeRevision,
    observed: bridge.body?.bridge?.actual?.runtimeRevision ?? null,
  }, { warning: bridge.ok && state === "reconnecting" });
add("bridge_compatibility", bridge.ok && bridge.body?.bridge?.compatible === true,
  bridge.body?.bridge ?? bridge.error, { warning: bridge.ok && state === "reconnecting" });

const report = {
  version: 3,
  status: checks.every((entry) => entry.passed) ? "healthy" : "degraded",
  checkedAt: new Date().toISOString(),
  checks,
  manualChecks: [
    "Use AkuSupervisor bridge validate after AkuBridge source changes.",
    "Confirm signed-in canonical X and LinkedIn feed tabs before a live session.",
    "Confirm one real codex-app-server invocation records structured output and token telemetry.",
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
    return { ok: response.ok, body: await response.json() };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}
function readJson(file) { return JSON.parse(fs.readFileSync(file, "utf8")); }
