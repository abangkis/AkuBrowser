import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.dirname(projectRoot);
const bridgeRoot = path.join(workspaceRoot, "AkuBridge");
const sidecarRoot = path.join(workspaceRoot, "AkuSidecar");

const browserPackage = readJson(path.join(projectRoot, "package.json"));
const bridgePackage = readJson(path.join(bridgeRoot, "package.json"));
const sidecarPackage = readJson(path.join(sidecarRoot, "package.json"));
const bridgeManifest = readJson(path.join(bridgeRoot, "manifest.json"));
assert.equal(bridgePackage.version, browserPackage.version, "AkuBridge package version drifted");
assert.equal(sidecarPackage.version, browserPackage.version, "AkuSidecar package version drifted");
assert.equal(bridgeManifest.version, browserPackage.version, "AkuBridge manifest version drifted");

const canonicalSchema = readJson(path.join(projectRoot, "contracts", "reasoning-result.schema.json"));
const sidecarSchema = readJson(path.join(sidecarRoot, "schemas", "reasoning-result.schema.json"));
assert.deepEqual(sidecarSchema, canonicalSchema, "AkuSidecar reasoning schema drifted from AkuBrowser");
const canonicalAcquisitionPlanSchema = readJson(
  path.join(projectRoot, "contracts", "acquisition-plan.schema.json"),
);
const sidecarAcquisitionPlanSchema = readJson(
  path.join(sidecarRoot, "schemas", "acquisition-plan.schema.json"),
);
assert.deepEqual(
  sidecarAcquisitionPlanSchema,
  canonicalAcquisitionPlanSchema,
  "AkuSidecar acquisition-plan schema drifted from AkuBrowser",
);
const canonicalUnifiedSessionSchema = readJson(
  path.join(projectRoot, "contracts", "unified-session.schema.json"),
);
const sidecarUnifiedSessionSchema = readJson(
  path.join(sidecarRoot, "schemas", "unified-session.schema.json"),
);
assert.deepEqual(
  sidecarUnifiedSessionSchema,
  canonicalUnifiedSessionSchema,
  "AkuSidecar unified-session schema drifted from AkuBrowser",
);
for (const schemaName of [
  "candidate-evaluation.schema.json",
  "preference-feedback.schema.json",
  "preference-profile.schema.json",
  "selection-decision.schema.json",
  "reasoning-invocation.schema.json",
  "onboarding-profile.schema.json",
  "calibration-session.schema.json",
  "calibration-label.schema.json",
  "calibration-profile-snapshot.schema.json",
]) {
  assert.deepEqual(
    readJson(path.join(sidecarRoot, "schemas", schemaName)),
    readJson(path.join(projectRoot, "contracts", schemaName)),
    `AkuSidecar ${schemaName} drifted from AkuBrowser`,
  );
}
assert.deepEqual(
  readJson(path.join(sidecarRoot, "config", "reasoning.json")),
  readJson(path.join(projectRoot, "contracts", "reasoning-routing-v0.json")),
  "AkuSidecar reasoning routing defaults drifted from AkuBrowser",
);

const bridgeService = readText(path.join(bridgeRoot, "service-worker.js"));
const bridgeCapabilities = readText(path.join(bridgeRoot, "bridge-capabilities.js"));
const bridgeTab = readText(path.join(bridgeRoot, "aku-browser-tab-bridge.js"));
const bridgeContent = readText(path.join(bridgeRoot, "content-script.js"));
const bridgeCapturePolicy = readText(path.join(bridgeRoot, "bounded-capture-policy.js"));
const sidecarHttp = readText(path.join(sidecarRoot, "src", "http", "app.mjs"));
const sidecarUi = readText(path.join(sidecarRoot, "public", "app.js"));
const sidecarContracts = readText(path.join(sidecarRoot, "src", "core", "contracts.mjs"));
const sidecarJobEngine = readText(path.join(sidecarRoot, "src", "core", "job-engine.mjs"));
const sidecarStateStore = readText(
  path.join(sidecarRoot, "src", "store", "sqlite-state-store.mjs"),
);
const sidecarBrowserAdapter = readText(
  path.join(sidecarRoot, "src", "browser", "browser-adapter-contract.mjs"),
);
assert.match(
  sidecarHttp,
  new RegExp(`APP_VERSION\\s*=\\s*["']${escapeRegExp(sidecarPackage.version)}["']`),
  "AkuSidecar HTTP version drifted from its package version",
);
assert.ok(bridgePackage.akuRuntimeRevision, "AkuBridge must declare an operational runtime revision");
assert.match(
  bridgeService + bridgeCapabilities,
  new RegExp(escapeRegExp(bridgePackage.akuRuntimeRevision)),
  "AkuBridge runtime revision drifted from its capability handshake",
);

for (const value of [
  "aku-browser.bridge.v1",
  "X-Aku-Bridge-Token",
  "X-Aku-Bridge-Id",
  "X-Aku-Bridge-Contract",
]) {
  assert.match(bridgeService + bridgeCapabilities, new RegExp(escapeRegExp(value)));
  assert.match(sidecarHttp, new RegExp(escapeRegExp(value)));
}

for (const value of [
  "AKU_BROWSER_BRIDGE_PING",
  "AKU_BROWSER_BRIDGE_READY",
  "AKU_BROWSER_DISPATCH",
  "AKU_BROWSER_BRIDGE_ERROR",
]) {
  assert.match(bridgeTab, new RegExp(escapeRegExp(value)));
  assert.match(sidecarUi, new RegExp(escapeRegExp(value)));
}

assert.match(bridgeService, /AKU_BROWSER_COLLECT_VISIBLE/);
assert.match(bridgeContent, /AKU_BROWSER_COLLECT_VISIBLE/);
for (const value of [
  "browserAdapter",
  "requestedScrolls",
  "performedScrolls",
  "scrollStopReason",
  "scrollContainer",
  "pendingNewContent",
  "pendingNewContentAction",
  "pendingContentActivationEvidence",
  "pendingContentPolicy",
  "feedMutation",
  "sameTabMutation",
  "restorationScope",
  "restoreAttempted",
  "restored",
  "feedPosition",
  "platformId",
  "acquisitionRound",
  "continuationRequested",
  "continuationAnchorMatched",
  "captureStartScrollY",
]) {
  assert.match(bridgeContent, new RegExp(escapeRegExp(value)));
  assert.match(sidecarContracts, new RegExp(escapeRegExp(value)));
}
assert.match(bridgeCapturePolicy, /maxScrolls: 2/);
assert.match(bridgeCapturePolicy, /sameTabMutationAllowed/);
assert.match(bridgeCapturePolicy, /acquisitionRound/);
assert.match(bridgeCapturePolicy, /continuation/);
assert.match(sidecarBrowserAdapter, /NATIVE_BROWSER_ADAPTER = "aku-bridge"/);
assert.match(
  sidecarBrowserAdapter,
  /pendingContentPolicy: revealPendingContent \? "reveal_if_present" : "detect_only"/,
);
assert.match(sidecarBrowserAdapter, /buildObservationContinuation/);
for (const value of [
  "evidenceKey",
  "eventKey",
  "knowledgeDelta",
  "exactDuplicatesSuppressed",
  "previousCheckpointRunId",
]) {
  assert.match(sidecarContracts + sidecarJobEngine, new RegExp(escapeRegExp(value)));
}
for (const table of [
  "checkpoints",
  "knowledge_events",
  "knowledge_versions",
  "evidence_dispositions",
  "candidate_evaluations",
  "preference_feedback_events",
  "reasoning_invocations",
]) {
  assert.match(sidecarStateStore, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`));
}
console.log("AkuBrowser cross-repository contracts are synchronized.");

function readJson(file) {
  return JSON.parse(readText(file));
}

function readText(file) {
  return fs.readFileSync(file, "utf8");
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
