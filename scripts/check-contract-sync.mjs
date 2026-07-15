import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const browserRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.dirname(browserRoot);
const bridgeRoot = path.join(workspaceRoot, "AkuBridge");
const sidecarRoot = path.join(workspaceRoot, "AkuSidecar");
const supervisorRoot = path.join(workspaceRoot, "AkuSupervisor");

const browserPackage = json(path.join(browserRoot, "package.json"));
const bridgePackage = json(path.join(bridgeRoot, "package.json"));
const bridgeManifest = json(path.join(bridgeRoot, "manifest.json"));
const sidecarConfig = json(path.join(sidecarRoot, "config", "sidecar.json"));
const supervisorProfile = json(path.join(supervisorRoot, "config", "akuworkspace.services.json"));

assert.match(browserPackage.version, /^\d+\.\d+\.\d+$/);
assert.equal(bridgePackage.version, "0.6.0");
assert.equal(bridgeManifest.version, bridgePackage.version);
assert.equal(bridgePackage.akuRuntimeRevision, "source-fidelity-v47");
assert.equal(sidecarConfig.reasoning.provider, "codex-app-server");
assert.equal(sidecarConfig.reasoning.executable, "runtime/codex-cli/bin/codex.exe");
assert.equal(fs.existsSync(path.join(sidecarRoot, "package.json")), false, "AkuSidecar must not retain a Node package");

const domain = text(path.join(sidecarRoot, "internal", "domain", "types.go"));
const engine = text(path.join(sidecarRoot, "internal", "engine", "engine.go"));
const reload = text(path.join(sidecarRoot, "internal", "engine", "reload_actions.go"));
const http = text(path.join(sidecarRoot, "internal", "httpapi", "server.go"));
const ui = text(path.join(sidecarRoot, "internal", "httpapi", "web", "app.js"));
const bridgeService = text(path.join(bridgeRoot, "service-worker.js"));
const bridgeCapabilities = text(path.join(bridgeRoot, "bridge-capabilities.js"));
const bridgeRelay = text(path.join(bridgeRoot, "aku-browser-tab-bridge.js"));
const activeContract = text(path.join(browserRoot, "contracts", "bridge-contract-v2.md"));

for (const value of ["1.0.0-dev.1", "aku-browser.bridge.v2"]) assert.match(domain, literal(value));
for (const value of ["0.6.0", "source-fidelity-v47"]) assert.match(engine, literal(value));
assert.match(reload, literal("aku-bridge-0.6.0-source-fidelity-v47"));

for (const value of [
  "x-dom-v16", "linkedin-dom-v13", "read_only_bounded",
  "probe_readiness", "probe_freshness", "recover_source_freshness",
  "collect_visible", "report_capture_quality", "recover_missing_media",
  "manage_capture_window", "release_capture_surface", "reload_self",
]) {
  assert.match(bridgeCapabilities, literal(value));
  assert.match(engine, literal(value));
}

for (const value of [
  "adapterVersions", "manifestVersion", "captureLimits", "adapterVersion",
  "selectorStrategy", "qualityReports", "platformId", "captureQuality",
  "mediaRecovery", "evidenceKey",
]) assert.match(domain, literal(value));

for (const value of [
  "X-Aku-Bridge-Token",
  "X-Aku-Bridge-Id",
  "X-Aku-Bridge-Contract",
  "/api/bridge/heartbeat",
  "/api/bridge/commands/next",
  "/api/operations/bridge/actions/reload-self",
]) assert.match(http, literal(value));

for (const value of [
  "AKU_BROWSER_BRIDGE_PING",
  "AKU_BROWSER_BRIDGE_READY",
  "AKU_BROWSER_DISPATCH",
  "AKU_BROWSER_BRIDGE_RELOAD_SELF",
  "AKU_BROWSER_BRIDGE_ERROR",
]) assert.match(ui + bridgeRelay, literal(value));

for (const value of ["aku-browser.bridge.v2", "source-fidelity-v47"]) {
  assert.match(bridgeService + bridgeCapabilities, literal(value));
  assert.match(activeContract, literal(value));
}

for (const schema of ["acquisition-plan.schema.json", "reasoning-result.schema.json"]) {
  assert.equal(
    digest(path.join(browserRoot, "contracts", schema)),
    digest(path.join(sidecarRoot, "schemas", schema)),
    `${schema} drifted between AkuBrowser and AkuSidecar`,
  );
}

const supervised = supervisorProfile.services.akusidecar;
assert.equal(supervised.command, "C:\\WorkspaceCodex\\AkuWorkspace\\AkuSidecar\\runtime\\dev\\aku-sidecar.exe");
assert.deepEqual(supervised.args, [
  "--config",
  "C:\\WorkspaceCodex\\AkuWorkspace\\AkuSidecar\\config\\sidecar.json",
  "--dev",
]);
assert.deepEqual(supervised.health.expect, {
  status: "ok",
  version: "1.0.0-dev.1",
  runtime: "go",
  bridgeContractVersion: "aku-browser.bridge.v2",
  provider: "codex-app-server",
});

console.log(JSON.stringify({
  status: "ok",
  boundary: "go-sidecar-v1",
  AkuBrowser: browserPackage.version,
  AkuBridge: bridgePackage.version,
  AkuBridgeRuntime: bridgePackage.akuRuntimeRevision,
  AkuSidecar: "1.0.0-dev.1",
  bridgeContract: "aku-browser.bridge.v2",
  provider: sidecarConfig.reasoning.provider,
}, null, 2));

function json(file) { return JSON.parse(fs.readFileSync(file, "utf8")); }
function text(file) { return fs.readFileSync(file, "utf8"); }
function digest(file) { return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex"); }
function literal(value) { return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")); }
