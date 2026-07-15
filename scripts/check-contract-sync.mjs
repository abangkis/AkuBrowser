import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  BRIDGE_RUNTIME_REVISION,
  createBridgeCapabilities,
} from "../../AkuBridge/bridge-capabilities.js";
import { BRIDGE_REQUIREMENTS } from "../../AkuSidecar/src/operations/bridge-compatibility.mjs";
import { BOUNDED_LOAD_PROFILES } from "../../AkuSidecar/src/core/bounded-load-profile.mjs";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.dirname(projectRoot);
const bridgeRoot = path.join(workspaceRoot, "AkuBridge");
const sidecarRoot = path.join(workspaceRoot, "AkuSidecar");

const browserPackage = readJson(path.join(projectRoot, "package.json"));
const bridgePackage = readJson(path.join(bridgeRoot, "package.json"));
const sidecarPackage = readJson(path.join(sidecarRoot, "package.json"));
const bridgeManifest = readJson(path.join(bridgeRoot, "manifest.json"));
const versionPattern = /^\d+\.\d+\.\d+$/;
for (const [component, version] of Object.entries({
  AkuBrowser: browserPackage.version,
  AkuBridge: bridgePackage.version,
  AkuSidecar: sidecarPackage.version,
})) {
  assert.match(version, versionPattern, `${component} must declare a semantic version`);
}
assert.equal(
  bridgeManifest.version,
  bridgePackage.version,
  "AkuBridge manifest drifted from its package version",
);
const declaredBridgeCapabilities = createBridgeCapabilities(bridgeManifest);
assert.ok(
  compareVersions(bridgePackage.version, BRIDGE_REQUIREMENTS.minimumExtensionVersion) >= 0,
  "AkuBridge is older than AkuSidecar's declared compatibility minimum",
);
assert.equal(
  BRIDGE_RUNTIME_REVISION,
  BRIDGE_REQUIREMENTS.runtimeRevision,
  "AkuBridge runtime revision drifted from AkuSidecar requirements",
);
assert.deepEqual(
  declaredBridgeCapabilities.adapterVersions,
  BRIDGE_REQUIREMENTS.adapterVersions,
  "AkuBridge adapter versions drifted from AkuSidecar requirements",
);
for (const action of BRIDGE_REQUIREMENTS.requiredActions) {
  assert.ok(
    declaredBridgeCapabilities.actions.includes(action),
    `AkuBridge must advertise Sidecar-required action ${action}`,
  );
}

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
for (const profile of Object.values(BOUNDED_LOAD_PROFILES)) {
  assert.ok(
    profile.maxScrolls <= declaredBridgeCapabilities.captureLimits.maxScrolls,
    `${profile.id} exceeds AkuBridge's declared scroll ceiling`,
  );
  assert.ok(
    profile.maxItemsPerSource <= canonicalUnifiedSessionSchema.properties.maxItemsPerSource.maximum,
    `${profile.id} exceeds the unified per-source schema ceiling`,
  );
  assert.ok(
    profile.maxItemsTotal <= canonicalUnifiedSessionSchema.properties.maxItemsTotal.maximum,
    `${profile.id} exceeds the unified total schema ceiling`,
  );
}
for (const schemaName of [
  "candidate-evaluation.schema.json",
  "preference-feedback.schema.json",
  "preference-profile.schema.json",
  "selection-decision.schema.json",
  "preference-eligibility-decision.schema.json",
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
const bridgeCapabilitiesSource = readText(path.join(bridgeRoot, "bridge-capabilities.js"));
const bridgeTab = readText(path.join(bridgeRoot, "aku-browser-tab-bridge.js"));
const bridgeContent = readText(path.join(bridgeRoot, "content-script.js"));
const bridgeFreshnessRecovery = readText(path.join(bridgeRoot, "source-freshness-recovery.js"));
const bridgeFreshnessRuntime = readText(path.join(bridgeRoot, "source-freshness-runtime.js"));
const bridgeMediaRecovery = readText(path.join(bridgeRoot, "media-recovery-runtime.js"));
const bridgeCapturePolicy = readText(path.join(bridgeRoot, "bounded-capture-policy.js"));
const bridgeQualityPolicy = readText(path.join(bridgeRoot, "capture-quality-policy.js"));
const sidecarHttp = readText(path.join(sidecarRoot, "src", "http", "app.mjs"));
const sidecarUi = readText(path.join(sidecarRoot, "public", "app.js"));
const sidecarContracts = readText(path.join(sidecarRoot, "src", "core", "contracts.mjs"));
const sidecarJobEngine = readText(path.join(sidecarRoot, "src", "core", "job-engine.mjs"));
const sidecarSelectionEngine = readText(path.join(sidecarRoot, "src", "core", "selection-engine.mjs"));
const sidecarPreferenceRuntime = readText(path.join(sidecarRoot, "src", "core", "preference-runtime.mjs"));
const sidecarPreferenceEligibility = readText(
  path.join(sidecarRoot, "src", "core", "preference-eligibility-controller.mjs"),
);
const sidecarPreferenceFeatures = readText(path.join(sidecarRoot, "src", "core", "preference-features.mjs"));
const sidecarEngineBenchmark = readText(path.join(sidecarRoot, "src", "core", "engine-replay-benchmark.mjs"));
const sidecarStateStore = readText(
  path.join(sidecarRoot, "src", "store", "sqlite-state-store.mjs"),
);
const sidecarBrowserAdapter = readText(
  path.join(sidecarRoot, "src", "browser", "browser-adapter-contract.mjs"),
);
const sidecarQualityAdmission = readText(
  path.join(sidecarRoot, "src", "browser", "observation-quality-policy.mjs"),
);
assert.match(
  sidecarHttp,
  new RegExp(`APP_VERSION\\s*=\\s*["']${escapeRegExp(sidecarPackage.version)}["']`),
  "AkuSidecar HTTP version drifted from its package version",
);
assert.ok(bridgePackage.akuRuntimeRevision, "AkuBridge must declare an operational runtime revision");
assert.match(
  bridgeService + bridgeCapabilitiesSource,
  new RegExp(escapeRegExp(bridgePackage.akuRuntimeRevision)),
  "AkuBridge runtime revision drifted from its capability handshake",
);

for (const value of [
  "aku-browser.bridge.v1",
  "X-Aku-Bridge-Token",
  "X-Aku-Bridge-Id",
  "X-Aku-Bridge-Contract",
]) {
  assert.match(bridgeService + bridgeCapabilitiesSource, new RegExp(escapeRegExp(value)));
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
  "sourceFreshness",
  "mediaRecovery",
]) {
  assert.match(bridgeContent, new RegExp(escapeRegExp(value)));
  assert.match(sidecarContracts, new RegExp(escapeRegExp(value)));
}
for (const value of [
  "source-freshness-recovery-v1",
  "pending_content_revealed",
  "feed_changed_after_wake",
  "adapter_wake_settled",
  "follow_up_preserved",
  "freshness_unavailable",
]) {
  assert.match(
    bridgeFreshnessRecovery + bridgeFreshnessRuntime + bridgeContent + sidecarContracts,
    new RegExp(escapeRegExp(value)),
  );
}
assert.match(
  readText(path.join(projectRoot, "contracts", "source-freshness-recovery-v1.md")),
  /generic source-freshness state machine|Generic ownership/i,
);
for (const value of [
  "media-recovery-v1",
  "primary_complete",
  "primary_hydration",
  "alternate_dom",
  "unavailable",
]) {
  assert.match(
    bridgeMediaRecovery + bridgeContent + sidecarContracts + sidecarQualityAdmission,
    new RegExp(escapeRegExp(value)),
  );
}
assert.match(
  readText(path.join(projectRoot, "contracts", "media-recovery-v1.md")),
  /Generic ownership/i,
);
assert.match(sidecarStateStore, /media_recovery_json/);
assert.match(sidecarUi, /source-layout-media-unavailable/);
assert.match(bridgeCapturePolicy, /maxScrolls: 6/);
assert.match(bridgeCapturePolicy, /sameTabMutationAllowed/);
assert.match(bridgeCapturePolicy, /acquisitionRound/);
assert.match(bridgeCapturePolicy, /continuation/);
assert.match(bridgeQualityPolicy, /social-post-v1/);
assert.match(bridgeQualityPolicy, /pending_hydration/);
assert.match(sidecarContracts, /pending_hydration/);
for (const value of [
  "complete",
  "usable_degraded",
  "retryable",
  "invalid",
]) {
  assert.match(bridgeQualityPolicy, new RegExp(escapeRegExp(value)));
  assert.match(sidecarQualityAdmission, new RegExp(escapeRegExp(value)));
}
assert.match(bridgeCapturePolicy, /maxQualityRetryBudget: 1/);
assert.match(sidecarBrowserAdapter, /qualityReportRequired/);
assert.match(sidecarJobEngine, /admitObservationQuality/);
assert.match(sidecarBrowserAdapter, /NATIVE_BROWSER_ADAPTER = "aku-bridge"/);
assert.match(
  sidecarBrowserAdapter,
  /pendingContentPolicy: revealPendingContent \? "reveal_if_present" : "detect_only"/,
);
assert.match(sidecarBrowserAdapter, /buildObservationContinuation/);
assert.match(sidecarSelectionEngine, /selection-engine-v1/);
assert.match(sidecarPreferenceRuntime, /preference-runtime-v2/);
assert.match(sidecarPreferenceEligibility, /preference-eligibility-v2/);
assert.match(sidecarPreferenceEligibility, /mode: "promote_unused_budget"/);
assert.match(sidecarPreferenceEligibility, /live_promotion_unused_budget/);
assert.match(sidecarPreferenceEligibility, /live_suppression_guarded/);
assert.doesNotMatch(sidecarPreferenceFeatures, /candidate\.source|assessment\.source/);
assert.match(sidecarEngineBenchmark, /benchmarkPerformsModelCalls: false/);
for (const contractName of [
  "selection-engine-v1.md",
  "preference-runtime-v2.md",
  "preference-eligibility-controller-v2.md",
  "engine-replay-benchmark-v1.md",
]) {
  assert.ok(fs.existsSync(path.join(projectRoot, "contracts", contractName)), `${contractName} is required`);
}
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
  "preference_eligibility_decisions",
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

function compareVersions(left, right) {
  const a = String(left).split(".").map(Number);
  const b = String(right).split(".").map(Number);
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] > b[index] ? 1 : -1;
  }
  return 0;
}
