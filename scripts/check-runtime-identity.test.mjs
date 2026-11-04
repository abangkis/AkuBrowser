import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { verifyRuntimeIdentity } from "./check-runtime-identity.mjs";

const identity = {
  version: "0.9.0",
  chromeVersion: "0.9.0.0",
  revision: "source-adapters-v106",
  focusPolicy: "quiet-containment-only-v2",
  contract: "aku-browser.bridge.v2",
  bridgeID: "aku-bridge-chrome-mv3-v0",
};

const checkerPath = fileURLToPath(new URL("./check-runtime-identity.mjs", import.meta.url));
const fixtureParent = fileURLToPath(new URL("../build/runtime-identity-tests/", import.meta.url)).replace(/[\\/]$/, "");
const candidatePath = "AkuBrowser/contracts/source-candidate-identity.json";
const releasePaths = [
  "AkuBrowser/release/release-manifest.json", "AkuBrowser/contracts/bridge-contract-v2.md",
  ...["native-runtime-ensure-request.json", "native-runtime-invalid-arbitrary-action.json",
    "native-runtime-v1-ensure-request.json", "native-runtime-ready-response.json",
    "native-runtime-v1-ready-response.json"].map((name) => `AkuBrowser/contracts/examples/${name}`),
];

async function removeFixture(root) {
  if (path.dirname(root) !== fixtureParent || await fs.realpath(root) !== root || (await fs.lstat(root)).isSymbolicLink()) {
    throw new Error("Refusing identity fixture cleanup outside the ordinary project build directory.");
  }
  await fs.rm(root, { recursive: true, force: true });
}

async function writeFile(root, relativePath, contents) {
  const file = path.join(root, relativePath);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, contents, "utf8");
}

async function createFixture() {
  await fs.mkdir(fixtureParent, { recursive: true });
  const root = await fs.mkdtemp(path.join(fixtureParent, "identity-"));
  const buildID = `aku-bridge-${identity.version}-${identity.revision}`;
  await writeFile(root, "AkuBrowser/release/release-manifest.json", JSON.stringify({
    distribution: { authorityRepository: "AkuBrowser" },
    components: {
      akuBridge: {
        version: identity.version,
        chromeVersion: identity.chromeVersion,
        runtimeRevision: identity.revision,
        focusPolicyRevision: identity.focusPolicy,
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
    `export const FOCUS_POLICY_REVISION = "${identity.focusPolicy}";`,
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
  await writeFile(root, "AkuSidecar/internal/engine/reload_actions.go", `const ExpectedBridgeBuildID = "${buildID}"\nconst ExpectedBridgeFocusPolicyRevision = "${identity.focusPolicy}"`);
  await writeFile(root, "AkuSidecar/internal/domain/types.go", [
    `const ApplicationVersion = "${identity.version}"`,
    `const BridgeContractVersion = "${identity.contract}"`,
  ].join("\n"));
  await writeFile(root, "AkuSidecar/README.md", `AkuBridge \`${identity.version}\` / \`${identity.revision}\``);
  return root;
}

test("accepts one exact integration identity without creating a runtime dependency", async (t) => {
  const root = await createFixture();
  t.after(() => removeFixture(root));

  const result = await verifyRuntimeIdentity(root);

  assert.equal(result.status, "ok");
  assert.equal(result.runtimeRevision, identity.revision);
  assert.equal(result.runtimeDependency, false);
  assert.equal(result.scope, "development-and-release-only");
});

test("fails before build when Sidecar expects a different Bridge revision", async (t) => {
  const root = await createFixture();
  t.after(() => removeFixture(root));
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
  t.after(() => removeFixture(root));
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
  assert.match(script, /actual\.focusPolicyRevision/);
  assert.match(script, /actual\.contractVersion/);
  assert.match(script, /Wait-ReleaseBridge/);
  assert.doesNotMatch(script, /Wait-CompatibleBridge/);
});

test("fails exact integration identity when Sidecar expects a different focus policy", async (t) => {
  const root = await createFixture();
  t.after(() => removeFixture(root));
  await writeFile(root, "AkuSidecar/internal/engine/reload_actions.go", [
    `const ExpectedBridgeBuildID = "aku-bridge-${identity.version}-${identity.revision}"`,
    'const ExpectedBridgeFocusPolicyRevision = "mutable-focus-authority-v1"',
  ].join("\n"));
  await assert.rejects(verifyRuntimeIdentity(root), /AkuSidecar focus policy: found "mutable-focus-authority-v1"/);
});

async function replaceFixtureText(root, file, from, to) {
  const original = await fs.readFile(path.join(root, file), "utf8");
  assert.ok(original.includes(from), `Missing fixture input: ${file}/${from}`);
  await writeFile(root, file, original.replaceAll(from, to));
}

async function candidateFixture(t) {
  const root = await createFixture();
  t.after(() => removeFixture(root));
  for (const file of releasePaths) {
    await replaceFixtureText(root, file, identity.revision, "source-adapters-v116");
  }
  for (const file of ["AkuBridge/package.json", "AkuBridge/bridge-capabilities.js", "AkuBridge/content-script.js",
    "AkuBridge/README.md", "AkuSidecar/internal/engine/engine.go", "AkuSidecar/internal/engine/reload_actions.go", "AkuSidecar/README.md"]) {
    await replaceFixtureText(root, file, identity.revision, "source-adapters-v118");
  }
  const manifest = {
    schema: "aku.source-candidate-identity.v1", authorityRepository: "AkuBrowser",
    components: {
      akuBridge: { version: identity.version, chromeVersion: identity.chromeVersion, runtimeRevision: "source-adapters-v118",
        focusPolicyRevision: identity.focusPolicy, contractVersion: identity.contract },
      akuSidecar: { version: identity.version, runtimeRevision: "source-adapters-v118" },
    },
  };
  await writeFile(root, candidatePath, JSON.stringify(manifest));
  return { root, manifest };
}

async function historicalBytes(root) {
  return Promise.all(releasePaths.map((file) => fs.readFile(path.join(root, file), "utf8")));
}

function cli(root, ...args) {
  return spawnSync(process.execPath, [checkerPath, root, ...args], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
}

test("explicit source candidate v118 passes with unchanged v116 release metadata and no release qualification", async (t) => {
  const { root } = await candidateFixture(t);
  const before = await historicalBytes(root);
  const result = await verifyRuntimeIdentity(root, { sourceCandidate: true });
  assert.equal(result.status, "ok");
  assert.equal(result.authority, "AkuBrowser/contracts/source-candidate-identity.json");
  assert.equal(result.runtimeRevision, "source-adapters-v118");
  assert.equal(result.buildId, `aku-bridge-${identity.version}-source-adapters-v118`);
  assert.equal(result.scope, "source-candidate-only");
  assert.equal(result.referenceAuthority, "AkuBrowser/release/release-manifest.json");
  assert.equal(result.referenceRuntimeRevision, "source-adapters-v116");
  assert.equal(result.releaseQualified, false);
  assert.equal(result.runtimeDependency, false);
  await assert.rejects(verifyRuntimeIdentity(root), /expected "source-adapters-v116"/);
  assert.deepEqual(await historicalBytes(root), before);
});

test("CLI requires the explicit candidate flag and emits a clearly scoped result", async (t) => {
  const { root } = await candidateFixture(t);
  const candidate = cli(root, "--source-candidate");
  assert.equal(candidate.status, 0, candidate.stderr);
  assert.equal(JSON.parse(candidate.stdout).scope, "source-candidate-only");
  assert.equal(JSON.parse(candidate.stdout).releaseQualified, false);
  const release = cli(root);
  assert.notEqual(release.status, 0);
  assert.equal(release.stdout, "");
  assert.match(release.stderr, /Canonical authority: AkuBrowser\/release\/release-manifest.json/);
});

test("release mode never reads a broken source candidate manifest", async (t) => {
  const root = await createFixture();
  t.after(() => removeFixture(root));
  await writeFile(root, candidatePath, "not JSON");
  const result = await verifyRuntimeIdentity(root);
  assert.equal(result.runtimeRevision, identity.revision);
  assert.equal(result.authority, "AkuBrowser/release/release-manifest.json");
  assert.equal(result.scope, "development-and-release-only");
});

for (const [name, file, from, to, label] of [
  ["package revision", "AkuBridge/package.json", "source-adapters-v118", "source-adapters-v119", "AkuBridge package runtime revision"],
  ["content revision", "AkuBridge/content-script.js", "source-adapters-v118", "source-adapters-v119", "AkuBridge content-script revision"],
  ["Sidecar revision", "AkuSidecar/internal/engine/engine.go", "source-adapters-v118", "source-adapters-v119", "AkuSidecar ExpectedBridgeRevision"],
  ["build ID", "AkuSidecar/internal/engine/reload_actions.go", "source-adapters-v118", "source-adapters-v119", "AkuSidecar ExpectedBridgeBuildID"],
  ["Bridge focus", "AkuBridge/bridge-capabilities.js", identity.focusPolicy, "mutable-focus-v1", "AkuBridge focus policy"],
  ["Sidecar focus", "AkuSidecar/internal/engine/reload_actions.go", identity.focusPolicy, "mutable-focus-v1", "AkuSidecar focus policy"],
  ["bootstrap", "AkuBridge/bridge-capabilities.js", 'SIDECAR_BOOTSTRAP_VERSION = "0.9.0"', 'SIDECAR_BOOTSTRAP_VERSION = "0.9.1"', "AkuBridge Sidecar bootstrap version"],
  ["contract", "AkuSidecar/internal/domain/types.go", identity.contract, "aku-browser.bridge.v3", "AkuSidecar Bridge contract"],
  ["Bridge ID", "AkuSidecar/internal/engine/engine.go", identity.bridgeID, "foreign-bridge", "AkuSidecar ExpectedBridgeID"],
  ["stale Bridge README", "AkuBridge/README.md", "source-adapters-v118", "source-adapters-v117", "AkuBridge README"],
  ["stale Sidecar README", "AkuSidecar/README.md", "source-adapters-v118", "source-adapters-v117", "AkuSidecar README"],
]) {
  test(`candidate mode preserves the ${name} guard`, async (t) => {
    const { root } = await candidateFixture(t);
    await replaceFixtureText(root, file, from, to);
    await assert.rejects(verifyRuntimeIdentity(root, { sourceCandidate: true }), (error) => {
      assert.ok(error.message.includes("Canonical authority: AkuBrowser/contracts/source-candidate-identity.json"), error.message);
      assert.ok(error.message.includes(label), error.message);
      return true;
    });
  });
}

for (const file of releasePaths.filter((file) => !file.endsWith("release-manifest.json"))) {
  test(`candidate mode still rejects a changed historical reference: ${path.basename(file)}`, async (t) => {
    const { root } = await candidateFixture(t);
    await replaceFixtureText(root, file, "source-adapters-v116", "source-adapters-v999");
    await assert.rejects(verifyRuntimeIdentity(root, { sourceCandidate: true }), (error) => {
      assert.ok(error.message.includes(path.basename(file)) || error.message.includes("AkuBrowser Bridge contract"), error.message);
      assert.ok(error.message.includes("source-adapters-v116"), error.message);
      return true;
    });
  });
}

for (const [name, change] of [
  ["schema", (m) => { m.schema = "unknown"; }],
  ["authority", (m) => { m.authorityRepository = "foreign"; }],
  ["unknown field", (m) => { m.allowMismatch = true; }],
  ["missing field", (m) => { delete m.components.akuBridge.runtimeRevision; }],
  ["invalid revision", (m) => { m.components.akuBridge.runtimeRevision = "v118"; }],
  ["empty focus", (m) => { m.components.akuBridge.focusPolicyRevision = ""; }],
  ["numeric version", (m) => { m.components.akuSidecar.version = 9; }],
  ["inconsistent revisions", (m) => { m.components.akuSidecar.runtimeRevision = "source-adapters-v119"; }],
  ["unknown component", (m) => { m.components.foreign = {}; }],
]) {
  test(`candidate manifest fails closed for ${name}`, async (t) => {
    const { root, manifest } = await candidateFixture(t);
    change(manifest);
    await writeFile(root, candidatePath, JSON.stringify(manifest));
    await assert.rejects(verifyRuntimeIdentity(root, { sourceCandidate: true }), /Invalid source candidate identity/);
  });
}

for (const content of [null, "{", "null", "[]"]) {
  test(`candidate manifest never falls back when missing or malformed: ${content}`, async (t) => {
    const { root } = await candidateFixture(t);
    if (content === null) await fs.unlink(path.join(root, candidatePath));
    else await writeFile(root, candidatePath, content);
    await assert.rejects(verifyRuntimeIdentity(root, { sourceCandidate: true }), /Invalid source candidate identity/);
  });
}

test("unknown API options and CLI selectors fail closed", async (t) => {
  const root = await createFixture();
  t.after(() => removeFixture(root));
  for (const options of [{ sourceCandidate: "true" }, { scope: "candidate" }, null]) {
    await assert.rejects(verifyRuntimeIdentity(root, options), /Invalid identity checker options/);
  }
  for (const args of [["--unknown"], ["--source-candidate", "--source-candidate"], ["extra-workspace"]]) {
    const result = cli(root, ...args);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /usage:/);
  }
});

for (const sourceCandidate of [false, true]) {
  for (const [file, key, label] of [
    ["AkuBridge/package.json", "akuRuntimeRevision", "AkuBridge package runtime revision"],
    ["AkuBridge/manifest.json", "version_name", "AkuBridge manifest version name"],
  ]) {
    test(`missing source field ${key} is rejected in ${sourceCandidate ? "candidate" : "release"} mode`, async (t) => {
      const root = sourceCandidate ? (await candidateFixture(t)).root : await createFixture();
      if (!sourceCandidate) t.after(() => removeFixture(root));
      const value = JSON.parse(await fs.readFile(path.join(root, file), "utf8"));
      delete value[key];
      await writeFile(root, file, JSON.stringify(value));
      await assert.rejects(verifyRuntimeIdentity(root, { sourceCandidate }), (error) => {
        assert.ok(error.message.includes(label), error.message);
        return true;
      });
    });
  }
}

test("candidate mode rejects a missing historical release authority", async (t) => {
  const { root } = await candidateFixture(t);
  const file = releasePaths[0];
  const value = JSON.parse(await fs.readFile(path.join(root, file), "utf8"));
  delete value.distribution.authorityRepository;
  await writeFile(root, file, JSON.stringify(value));
  await assert.rejects(verifyRuntimeIdentity(root, { sourceCandidate: true }), /release distribution authority/);
});
