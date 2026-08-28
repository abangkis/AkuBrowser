import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { verifyRuntimeIdentity } from "./check-runtime-identity.mjs";

const identity = {
  version: "0.9.0",
  chromeVersion: "0.9.0.0",
  revision: "source-adapters-v106",
  contract: "aku-browser.bridge.v2",
  bridgeID: "aku-bridge-chrome-mv3-v0",
};

async function writeFile(root, relativePath, contents) {
  const file = path.join(root, relativePath);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, contents, "utf8");
}

async function createFixture() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "aku-runtime-identity-"));
  const buildID = `aku-bridge-${identity.version}-${identity.revision}`;
  await writeFile(root, "AkuBrowser/release/release-manifest.json", JSON.stringify({
    distribution: { authorityRepository: "AkuBrowser" },
    components: {
      akuBridge: {
        version: identity.version,
        chromeVersion: identity.chromeVersion,
        runtimeRevision: identity.revision,
        contractVersion: identity.contract,
      },
      akuSidecar: { version: identity.version, runtimeRevision: identity.revision },
    },
  }));
  await writeFile(root, "AkuBrowser/contracts/bridge-contract-v2.md", `runtime revision \`${identity.revision}\`\nbuild id \`${buildID}\``);
  for (const file of ["native-runtime-ensure-request.json", "native-runtime-invalid-arbitrary-action.json", "native-runtime-v1-ensure-request.json"]) {
    await writeFile(root, `AkuBrowser/contracts/examples/${file}`, JSON.stringify({ extension: {
      productVersion: identity.version,
      runtimeRevision: identity.revision,
      bridgeContractVersion: identity.contract,
    } }));
  }
  await writeFile(root, "AkuBrowser/contracts/examples/native-runtime-ready-response.json", JSON.stringify({ runtime: {
    version: identity.version,
    runtimeRevision: identity.revision,
    bridgeContractVersion: identity.contract,
  } }));
  await writeFile(root, "AkuBrowser/contracts/examples/native-runtime-v1-ready-response.json", JSON.stringify({ runtime: {
    version: identity.version,
    runtimeRevision: identity.revision,
    bridgeContractVersion: identity.contract,
  } }));
  await writeFile(root, "AkuBridge/package.json", JSON.stringify({ version: identity.version, akuRuntimeRevision: identity.revision }));
  await writeFile(root, "AkuBridge/manifest.json", JSON.stringify({ version: identity.chromeVersion, version_name: identity.version }));
  await writeFile(root, "AkuBridge/bridge-capabilities.js", [
    `export const BRIDGE_RUNTIME_REVISION = "${identity.revision}";`,
    `export const BRIDGE_ID = "${identity.bridgeID}";`,
    `export const BRIDGE_CONTRACT_VERSION = "${identity.contract}";`,
    `export const SIDECAR_BOOTSTRAP_VERSION = "${identity.version}";`,
    "const capability = { buildId: `aku-bridge-${extensionVersion}-${BRIDGE_RUNTIME_REVISION}` };",
  ].join("\n"));
  await writeFile(root, "AkuBridge/content-script.js", `const runtimeRevision = "${identity.revision}";`);
  await writeFile(root, "AkuBridge/README.md", `runtime **\`${identity.revision}\`**`);
  await writeFile(root, "AkuSidecar/internal/engine/engine.go", [
    `const ExpectedBridgeVersion = "${identity.version}"`,
    `const ExpectedBridgeRevision = "${identity.revision}"`,
    `const ExpectedBridgeID = "${identity.bridgeID}"`,
  ].join("\n"));
  await writeFile(root, "AkuSidecar/internal/engine/reload_actions.go", `const ExpectedBridgeBuildID = "${buildID}"`);
  await writeFile(root, "AkuSidecar/internal/domain/types.go", [
    `const ApplicationVersion = "${identity.version}"`,
    `const BridgeContractVersion = "${identity.contract}"`,
  ].join("\n"));
  await writeFile(root, "AkuSidecar/README.md", `AkuBridge \`${identity.version}\` / \`${identity.revision}\``);
  return root;
}

test("accepts one exact integration identity without creating a runtime dependency", async (t) => {
  const root = await createFixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const result = await verifyRuntimeIdentity(root);

  assert.equal(result.status, "ok");
  assert.equal(result.runtimeRevision, identity.revision);
  assert.equal(result.runtimeDependency, false);
  assert.equal(result.scope, "development-and-release-only");
});

test("fails before build when Sidecar expects a different Bridge revision", async (t) => {
  const root = await createFixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await writeFile(root, "AkuSidecar/internal/engine/engine.go", [
    `const ExpectedBridgeVersion = "${identity.version}"`,
    "const ExpectedBridgeRevision = \"source-adapters-v89\"",
    `const ExpectedBridgeID = "${identity.bridgeID}"`,
  ].join("\n"));

  await assert.rejects(
    verifyRuntimeIdentity(root),
    /AkuSidecar ExpectedBridgeRevision: found "source-adapters-v89", expected "source-adapters-v106"/,
  );
});

test("fails before packaging when Bridge pins a different Sidecar bootstrap version", async (t) => {
  const root = await createFixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const capabilitiesPath = path.join(root, "AkuBridge", "bridge-capabilities.js");
  const capabilities = await fs.readFile(capabilitiesPath, "utf8");
  await fs.writeFile(
    capabilitiesPath,
    capabilities.replace('SIDECAR_BOOTSTRAP_VERSION = "0.9.0"', 'SIDECAR_BOOTSTRAP_VERSION = "0.9.1"'),
    "utf8",
  );

  await assert.rejects(
    verifyRuntimeIdentity(root),
    /AkuBridge Sidecar bootstrap version: found "0.9.1", expected "0.9.0"/,
  );
});

test("local release reconciliation requires the exact Bridge release identity", async () => {
  const script = await fs.readFile(
    new URL("./prepare-local-release.ps1", import.meta.url),
    "utf8",
  );
  assert.match(script, /function Test-BridgeMatchesRelease/);
  assert.match(script, /actual\.runtimeRevision/);
  assert.match(script, /actual\.buildId/);
  assert.match(script, /actual\.contractVersion/);
  assert.match(script, /Wait-ReleaseBridge/);
  assert.doesNotMatch(script, /Wait-CompatibleBridge/);
});
