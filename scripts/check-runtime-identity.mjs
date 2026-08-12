import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const scriptDirectory = path.dirname(scriptPath);

async function readJson(file) {
  return JSON.parse(await fs.readFile(file, "utf8"));
}

async function readText(file) {
  return fs.readFile(file, "utf8");
}

function capture(text, pattern, label, mismatches) {
  const match = text.match(pattern);
  if (!match) {
    mismatches.push(`${label}: declaration is missing`);
    return undefined;
  }
  return match[1];
}

function compare(label, actual, expected, mismatches) {
  if (actual !== undefined && actual !== expected) {
    mismatches.push(`${label}: found ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`);
  }
}

function requireText(label, text, expectedText, mismatches) {
  if (!text.includes(expectedText)) {
    mismatches.push(`${label}: missing ${JSON.stringify(expectedText)}`);
  }
}

export async function verifyRuntimeIdentity(workspaceRoot) {
  const browserRoot = path.join(workspaceRoot, "AkuBrowser");
  const bridgeRoot = path.join(workspaceRoot, "AkuBridge");
  const sidecarRoot = path.join(workspaceRoot, "AkuSidecar");
  const mismatches = [];

  const release = await readJson(path.join(browserRoot, "release", "release-manifest.json"));
  const bridgePackage = await readJson(path.join(bridgeRoot, "package.json"));
  const bridgeManifest = await readJson(path.join(bridgeRoot, "manifest.json"));
  const bridgeCapabilities = await readText(path.join(bridgeRoot, "bridge-capabilities.js"));
  const bridgeContentScript = await readText(path.join(bridgeRoot, "content-script.js"));
  const bridgeReadme = await readText(path.join(bridgeRoot, "README.md"));
  const sidecarEngine = await readText(path.join(sidecarRoot, "internal", "engine", "engine.go"));
  const sidecarReloadActions = await readText(path.join(sidecarRoot, "internal", "engine", "reload_actions.go"));
  const sidecarDomain = await readText(path.join(sidecarRoot, "internal", "domain", "types.go"));
  const sidecarReadme = await readText(path.join(sidecarRoot, "README.md"));
  const bridgeContract = await readText(path.join(browserRoot, "contracts", "bridge-contract-v2.md"));

  const canonical = {
    productVersion: release.components?.akuBridge?.version,
    chromeVersion: release.components?.akuBridge?.chromeVersion,
    runtimeRevision: release.components?.akuBridge?.runtimeRevision,
    contractVersion: release.components?.akuBridge?.contractVersion,
    sidecarVersion: release.components?.akuSidecar?.version,
    sidecarRuntimeRevision: release.components?.akuSidecar?.runtimeRevision,
  };
  canonical.buildId = `aku-bridge-${canonical.productVersion}-${canonical.runtimeRevision}`;

  compare("release distribution authority", release.distribution?.authorityRepository, "AkuBrowser", mismatches);
  if (!/^source-adapters-v[1-9][0-9]*$/.test(canonical.runtimeRevision ?? "")) {
    mismatches.push(`release runtime revision: invalid ${JSON.stringify(canonical.runtimeRevision)}`);
  }

  compare("AkuBridge package version", bridgePackage.version, canonical.productVersion, mismatches);
  compare("AkuBridge package runtime revision", bridgePackage.akuRuntimeRevision, canonical.runtimeRevision, mismatches);
  compare("AkuBridge manifest version name", bridgeManifest.version_name, canonical.productVersion, mismatches);
  compare("AkuBridge Chrome manifest version", bridgeManifest.version, canonical.chromeVersion, mismatches);

  const capabilityRevision = capture(bridgeCapabilities, /BRIDGE_RUNTIME_REVISION\s*=\s*"([^"]+)"/, "AkuBridge capability revision", mismatches);
  const capabilityContract = capture(bridgeCapabilities, /BRIDGE_CONTRACT_VERSION\s*=\s*"([^"]+)"/, "AkuBridge capability contract", mismatches);
  const capabilityBridgeID = capture(bridgeCapabilities, /BRIDGE_ID\s*=\s*"([^"]+)"/, "AkuBridge capability ID", mismatches);
  const sidecarBootstrapVersion = capture(
    bridgeCapabilities,
    /SIDECAR_BOOTSTRAP_VERSION\s*=\s*"([^"]+)"/,
    "AkuBridge Sidecar bootstrap version",
    mismatches,
  );
  compare("AkuBridge capability revision", capabilityRevision, canonical.runtimeRevision, mismatches);
  compare("AkuBridge capability contract", capabilityContract, canonical.contractVersion, mismatches);
  compare("AkuBridge Sidecar bootstrap version", sidecarBootstrapVersion, canonical.sidecarVersion, mismatches);
  requireText(
    "AkuBridge capability build ID",
    bridgeCapabilities,
    "buildId: `aku-bridge-${extensionVersion}-${BRIDGE_RUNTIME_REVISION}`",
    mismatches,
  );
  compare(
    "AkuBridge content-script revision",
    capture(bridgeContentScript, /const runtimeRevision\s*=\s*"([^"]+)"/, "AkuBridge content-script revision", mismatches),
    canonical.runtimeRevision,
    mismatches,
  );

  compare(
    "AkuSidecar ExpectedBridgeVersion",
    capture(sidecarEngine, /ExpectedBridgeVersion\s*=\s*"([^"]+)"/, "AkuSidecar ExpectedBridgeVersion", mismatches),
    canonical.productVersion,
    mismatches,
  );
  compare(
    "AkuSidecar ExpectedBridgeRevision",
    capture(sidecarEngine, /ExpectedBridgeRevision\s*=\s*"([^"]+)"/, "AkuSidecar ExpectedBridgeRevision", mismatches),
    canonical.runtimeRevision,
    mismatches,
  );
  compare(
    "AkuSidecar ExpectedBridgeID",
    capture(sidecarEngine, /ExpectedBridgeID\s*=\s*"([^"]+)"/, "AkuSidecar ExpectedBridgeID", mismatches),
    capabilityBridgeID,
    mismatches,
  );
  compare(
    "AkuSidecar ExpectedBridgeBuildID",
    capture(sidecarReloadActions, /ExpectedBridgeBuildID\s*=\s*"([^"]+)"/, "AkuSidecar ExpectedBridgeBuildID", mismatches),
    canonical.buildId,
    mismatches,
  );
  compare(
    "AkuSidecar application version",
    capture(sidecarDomain, /ApplicationVersion\s*=\s*"([^"]+)"/, "AkuSidecar application version", mismatches),
    canonical.sidecarVersion,
    mismatches,
  );
  compare(
    "AkuSidecar Bridge contract",
    capture(sidecarDomain, /BridgeContractVersion\s*=\s*"([^"]+)"/, "AkuSidecar Bridge contract", mismatches),
    canonical.contractVersion,
    mismatches,
  );

  requireText("AkuBrowser Bridge contract", bridgeContract, `runtime revision \`${canonical.runtimeRevision}\``, mismatches);
  requireText("AkuBrowser Bridge contract", bridgeContract, `build id \`${canonical.buildId}\``, mismatches);
  requireText("AkuBridge README", bridgeReadme, `runtime **\`${canonical.runtimeRevision}\`**`, mismatches);
  requireText("AkuSidecar README", sidecarReadme, `AkuBridge \`${canonical.productVersion}\` / \`${canonical.runtimeRevision}\``, mismatches);

  for (const file of [
    "native-runtime-ensure-request.json",
    "native-runtime-invalid-arbitrary-action.json",
    "native-runtime-v1-ensure-request.json",
  ]) {
    const example = (await readJson(path.join(browserRoot, "contracts", "examples", file))).extension;
    compare(`${file} product version`, example.productVersion, canonical.productVersion, mismatches);
    compare(`${file} runtime revision`, example.runtimeRevision, canonical.runtimeRevision, mismatches);
    compare(`${file} Bridge contract`, example.bridgeContractVersion, canonical.contractVersion, mismatches);
  }
  for (const file of ["native-runtime-ready-response.json", "native-runtime-v1-ready-response.json"]) {
    const runtime = (await readJson(path.join(browserRoot, "contracts", "examples", file))).runtime;
    compare(`${file} Sidecar version`, runtime.version, canonical.sidecarVersion, mismatches);
    compare(`${file} Sidecar runtime revision`, runtime.runtimeRevision, canonical.sidecarRuntimeRevision, mismatches);
    compare(`${file} Bridge contract`, runtime.bridgeContractVersion, canonical.contractVersion, mismatches);
  }

  if (mismatches.length > 0) {
    throw new Error([
      "Runtime identity contract mismatch.",
      `Canonical authority: AkuBrowser/release/release-manifest.json (${canonical.buildId})`,
      ...mismatches.map((message) => `- ${message}`),
    ].join("\n"));
  }

  return {
    status: "ok",
    authority: "AkuBrowser/release/release-manifest.json",
    productVersion: canonical.productVersion,
    chromeVersion: canonical.chromeVersion,
    runtimeRevision: canonical.runtimeRevision,
    buildId: canonical.buildId,
    contractVersion: canonical.contractVersion,
    scope: "development-and-release-only",
    runtimeDependency: false,
  };
}

async function main() {
  const workspaceRoot = path.resolve(process.argv[2] ?? path.join(scriptDirectory, "..", ".."));
  const result = await verifyRuntimeIdentity(workspaceRoot);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
