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

add("component_versions", new Set([
  browserPackage.version,
  bridgePackage.version,
  bridgeManifest.version,
  sidecarPackage.version,
]).size === 1, {
  AkuBrowser: browserPackage.version,
  AkuBridge: bridgePackage.version,
  AkuBridgeManifest: bridgeManifest.version,
  AkuSidecar: sidecarPackage.version,
});

const health = await safeFetch("http://127.0.0.1:47821/api/health");
add("sidecar_health", health.ok && health.body?.status === "ok", health.body ?? health.error);
const database = await safeFetch("http://127.0.0.1:47821/api/operations/database/health");
add("database_integrity", database.ok && database.body?.database?.status === "healthy", database.body ?? database.error);

const report = {
  version: 1,
  status: checks.every((entry) => entry.passed) ? "healthy" : "degraded",
  checkedAt: new Date().toISOString(),
  checks,
  manualChecks: [
    "Reload unpacked AkuBridge after extension source changes.",
    "Confirm signed-in canonical X and LinkedIn feed tabs when fail-fast behavior is desired.",
  ],
  mutationsPerformed: false,
};
console.log(JSON.stringify(report, null, 2));
if (report.status !== "healthy") process.exitCode = 1;

function add(id, passed, detail) {
  checks.push({ id, passed: passed === true, detail });
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
