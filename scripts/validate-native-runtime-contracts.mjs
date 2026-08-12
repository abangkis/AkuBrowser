import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (relativePath) => JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));

function fail(message) {
  throw new Error(`Native runtime contract validation failed: ${message}`);
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function jsonEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function resolveLocalRef(rootSchema, reference) {
  if (!reference.startsWith("#/")) fail(`unsupported schema reference ${reference}`);
  return reference.slice(2).split("/").reduce((value, segment) => {
    const key = segment.replaceAll("~1", "/").replaceAll("~0", "~");
    return value?.[key];
  }, rootSchema);
}

function schemaAccepts(rootSchema, schema, value) {
  if (schema === true) return true;
  if (schema === false || !schema || typeof schema !== "object") return false;
  if (schema.$ref && !schemaAccepts(rootSchema, resolveLocalRef(rootSchema, schema.$ref), value)) return false;
  if (schema.const !== undefined && !jsonEqual(value, schema.const)) return false;
  if (schema.enum && !schema.enum.some((item) => jsonEqual(value, item))) return false;
  if (schema.oneOf && schema.oneOf.filter((item) => schemaAccepts(rootSchema, item, value)).length !== 1) return false;
  if (schema.allOf && !schema.allOf.every((item) => schemaAccepts(rootSchema, item, value))) return false;
  if (schema.not && schemaAccepts(rootSchema, schema.not, value)) return false;
  if (schema.if) {
    const branch = schemaAccepts(rootSchema, schema.if, value) ? schema.then : schema.else;
    if (branch && !schemaAccepts(rootSchema, branch, value)) return false;
  }

  const actualType = value === null
    ? "null"
    : Array.isArray(value)
      ? "array"
      : Number.isInteger(value)
        ? "integer"
        : typeof value;
  if (schema.type) {
    const allowedTypes = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!allowedTypes.includes(actualType)) return false;
  }

  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) return false;
    if (schema.maxLength !== undefined && value.length > schema.maxLength) return false;
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) return false;
    if (schema.format === "date-time" && !Number.isFinite(Date.parse(value))) return false;
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) return false;
    if (schema.maximum !== undefined && value > schema.maximum) return false;
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) return false;
    if (schema.maxItems !== undefined && value.length > schema.maxItems) return false;
    if (schema.uniqueItems && new Set(value.map((item) => JSON.stringify(item))).size !== value.length) return false;
    if (schema.items && !value.every((item) => schemaAccepts(rootSchema, schema.items, item))) return false;
    if (schema.contains && !value.some((item) => schemaAccepts(rootSchema, schema.contains, item))) return false;
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    for (const required of schema.required ?? []) if (!hasOwn(value, required)) return false;
    const declared = schema.properties ?? {};
    for (const [key, propertySchema] of Object.entries(declared)) {
      if (hasOwn(value, key) && !schemaAccepts(rootSchema, propertySchema, value[key])) return false;
    }
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) if (!hasOwn(declared, key)) return false;
    }
  }
  return true;
}

function assertSchemaAccepts(schema, value, label) {
  if (!schemaAccepts(schema, schema, value)) fail(`${label} is rejected by its JSON Schema`);
}

function assertSchemaRejects(schema, value, label) {
  if (schemaAccepts(schema, schema, value)) fail(`${label} is unexpectedly accepted by its JSON Schema`);
}

function assertExactKeys(value, required, optional, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be an object`);
  for (const key of required) if (!hasOwn(value, key)) fail(`${label} is missing ${key}`);
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(`${label} has unknown property ${key}`);
}

function assertPattern(value, pattern, label) {
  if (typeof value !== "string" || !pattern.test(value)) fail(`${label} is invalid`);
}

const versions = /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/;
const revisions = /^[a-z0-9][a-z0-9._-]{2,79}$/;
const requestIds = /^[A-Za-z0-9._-]{16,80}$/;
const capabilities = /^[a-z][a-z0-9._-]{1,79}$/;
const v1Actions = new Set(["status", "ensure_runtime", "shutdown_if_idle", "check_codex"]);
const v2Actions = new Set([...v1Actions, "reconcile_runtime"]);
const phases = new Set(["idle", "checking", "downloading", "verifying", "staging", "waiting_for_idle", "swapping", "health_check", "rolling_back"]);
const statuses = new Set(["ready", "updating", "restart_required", "busy", "incompatible", "error"]);
const processStates = new Set(["stopped", "starting", "ready", "stopping", "failed"]);
const urgency = new Set(["routine", "recommended", "required", "security"]);

function validateExtension(extension, protocol) {
  const v2 = protocol === 2;
  assertExactKeys(
    extension,
    ["product", "productVersion", "runtimeRevision", "bridgeContractVersion", ...(v2 ? ["bridgeProtocol", "capabilities"] : [])],
    [],
    "extension",
  );
  if (extension.product !== "AkuBrowser" || extension.bridgeContractVersion !== "aku-browser.bridge.v2") fail("extension identity is invalid");
  assertPattern(extension.productVersion, versions, "extension productVersion");
  assertPattern(extension.runtimeRevision, revisions, "extension runtimeRevision");
  if (!v2) return;
  assertExactKeys(extension.bridgeProtocol, ["name", "version"], [], "bridgeProtocol");
  if (extension.bridgeProtocol.name !== "aku-browser.bridge" || extension.bridgeProtocol.version !== 2) fail("Bridge protocol is invalid");
  if (!Array.isArray(extension.capabilities) || extension.capabilities.length < 1 || extension.capabilities.length > 64) fail("capabilities are outside bounds");
  if (new Set(extension.capabilities).size !== extension.capabilities.length) fail("capabilities contain duplicates");
  for (const capability of extension.capabilities) assertPattern(capability, capabilities, "capability");
  for (const required of ["authority.read_only_bounded", "capture.bounded"]) {
    if (!extension.capabilities.includes(required)) fail(`capabilities are missing ${required}`);
  }
}

function validateRequest(value, protocol, shouldAccept = true) {
  let accepted = true;
  try {
    assertExactKeys(value, ["schemaVersion", "kind", "requestId", "action", "extension"], [], "request");
    if (value.schemaVersion !== protocol || value.kind !== "request") fail("request protocol identity is invalid");
    assertPattern(value.requestId, requestIds, "requestId");
    if (!(protocol === 2 ? v2Actions : v1Actions).has(value.action)) fail("request action is invalid");
    validateExtension(value.extension, protocol);
  } catch (error) {
    accepted = false;
    if (shouldAccept) throw error;
  }
  if (!shouldAccept && accepted) fail("invalid request example was accepted");
}

function validateRuntime(runtime) {
  if (runtime === null) return;
  assertExactKeys(runtime, ["version", "channel", "runtimeRevision", "bridgeContractVersion", "endpoint", "instanceEpoch", "processState"], [], "runtime");
  assertPattern(runtime.version, versions, "runtime version");
  assertPattern(runtime.runtimeRevision, revisions, "runtime revision");
  if (!["stable", "preview"].includes(runtime.channel) || runtime.bridgeContractVersion !== "aku-browser.bridge.v2") fail("runtime identity is invalid");
  if (!["http://127.0.0.1:11122", "http://localhost:11122"].includes(runtime.endpoint)) fail("runtime endpoint is invalid");
  if (!processStates.has(runtime.processState)) fail("runtime processState is invalid");
}

function validateUpdate(update, protocol) {
  assertExactKeys(update, ["phase", "currentVersion", "targetVersion", "rollbackAvailable"], protocol === 2 ? ["urgency", "deadline"] : [], "update");
  if (!phases.has(update.phase) || typeof update.rollbackAvailable !== "boolean") fail("update state is invalid");
  for (const value of [update.currentVersion, update.targetVersion]) if (value !== null) assertPattern(value, versions, "update version");
  if (hasOwn(update, "urgency") && !urgency.has(update.urgency)) fail("update urgency is invalid");
  if (hasOwn(update, "deadline") && (!Number.isFinite(Date.parse(update.deadline)) || !["required", "security"].includes(update.urgency))) fail("update deadline is invalid");
}

function validateResponse(value, protocol) {
  assertExactKeys(value, ["schemaVersion", "kind", "requestId", "action", "status", "runtime", "update", "error"], value.action === "check_codex" ? ["codex"] : [], "response");
  if (value.schemaVersion !== protocol || value.kind !== "response" || !(protocol === 2 ? v2Actions : v1Actions).has(value.action) || !statuses.has(value.status)) fail("response identity is invalid");
  assertPattern(value.requestId, requestIds, "response requestId");
  validateRuntime(value.runtime);
  validateUpdate(value.update, protocol);
  if (value.action === "check_codex") {
    assertExactKeys(value.codex, ["status"], [], "codex");
    if (!["available", "not_found", "error"].includes(value.codex.status)) fail("Codex status is invalid");
  } else if (hasOwn(value, "codex")) fail("codex is only valid for check_codex");
}

const v2Schema = readJson("contracts/native-runtime-messaging.schema.json");
const v1Schema = readJson("contracts/native-runtime-messaging-v1.schema.json");
if (v2Schema.$defs?.protocolVersion?.const !== 2 || v1Schema.$defs?.protocolVersion?.const !== 1) fail("schema protocol versions are not split");
if (!v2Schema.$defs?.action?.enum?.includes("reconcile_runtime") || v1Schema.$defs?.action?.enum?.includes("reconcile_runtime")) fail("v2-only reconcile action drifted");
if (v1Schema.$defs?.extensionIdentity?.properties?.bridgeProtocol || v1Schema.$defs?.updateState?.properties?.urgency) fail("frozen v1 schema gained v2 fields");
if (v2Schema.$defs?.extensionIdentity?.additionalProperties !== false || v1Schema.$defs?.extensionIdentity?.additionalProperties !== false) fail("extension identities are not strict");

const v2Request = readJson("contracts/examples/native-runtime-ensure-request.json");
const v2Response = readJson("contracts/examples/native-runtime-ready-response.json");
const v1Request = readJson("contracts/examples/native-runtime-v1-ensure-request.json");
const v1Response = readJson("contracts/examples/native-runtime-v1-ready-response.json");
const invalidRequest = readJson("contracts/examples/native-runtime-invalid-arbitrary-action.json");
validateRequest(v2Request, 2);
validateResponse(v2Response, 2);
validateRequest(v1Request, 1);
validateResponse(v1Response, 1);
validateRequest(invalidRequest, 2, false);
assertSchemaAccepts(v2Schema, v2Request, "v2 request example");
assertSchemaAccepts(v2Schema, v2Response, "v2 response example");
assertSchemaAccepts(v1Schema, v1Request, "v1 request example");
assertSchemaAccepts(v1Schema, v1Response, "v1 response example");
assertSchemaRejects(v2Schema, invalidRequest, "invalid arbitrary-action example");
assertSchemaRejects(v1Schema, v2Request, "v2 request at the frozen v1 boundary");

process.stdout.write(`${JSON.stringify({ status: "ok", currentProtocol: 2, frozenProtocol: 1, examplesValidated: 5 })}\n`);
