import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.dirname(projectRoot);
const bridgeRoot = path.join(workspaceRoot, "AkuBridge");
const sidecarRoot = path.join(workspaceRoot, "AkuSidecar");

const canonicalSchema = readJson(path.join(projectRoot, "contracts", "reasoning-result.schema.json"));
const sidecarSchema = readJson(path.join(sidecarRoot, "schemas", "reasoning-result.schema.json"));
assert.deepEqual(sidecarSchema, canonicalSchema, "AkuSidecar reasoning schema drifted from AkuBrowser");

const bridgeService = readText(path.join(bridgeRoot, "service-worker.js"));
const bridgeTab = readText(path.join(bridgeRoot, "aku-browser-tab-bridge.js"));
const bridgeContent = readText(path.join(bridgeRoot, "content-script.js"));
const sidecarHttp = readText(path.join(sidecarRoot, "src", "http", "app.mjs"));
const sidecarUi = readText(path.join(sidecarRoot, "public", "app.js"));

for (const value of [
  "aku-browser.bridge.v1",
  "X-Aku-Bridge-Token",
  "X-Aku-Bridge-Id",
  "X-Aku-Bridge-Contract",
]) {
  assert.match(bridgeService, new RegExp(escapeRegExp(value)));
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
