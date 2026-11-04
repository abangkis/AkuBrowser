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
  if (actual !== expected) {
    mismatches.push(`${label}: found ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`);
  }
}

function requireText(label, text, expectedText, mismatches) {
  if (!text.includes(expectedText)) {
    mismatches.push(`${label}: missing ${JSON.stringify(expectedText)}`);
  }
}

function identityTuple(reference) {
  const components = reference.components;
  const tuple = {
    productVersion: components?.akuBridge?.version,
    chromeVersion: components?.akuBridge?.chromeVersion,
    runtimeRevision: components?.akuBridge?.runtimeRevision,
    focusPolicyRevision: components?.akuBridge?.focusPolicyRevision,
    contractVersion: components?.akuBridge?.contractVersion,
    sidecarVersion: components?.akuSidecar?.version,
    sidecarRuntimeRevision: components?.akuSidecar?.runtimeRevision,
  };
  tuple.buildId = `aku-bridge-${tuple.productVersion}-${tuple.runtimeRevision}`;
  return tuple;
}

function requireKeys(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key))) {
    throw new Error(`${label} must contain exactly: ${keys.join(", ")}`);
  }
}

async function readSourceCandidate(browserRoot) {
  try {
    const candidate = await readJson(path.join(browserRoot, "contracts", "source-candidate-identity.json"));
    requireKeys(candidate, ["schema", "authorityRepository", "components"], "candidate");
    if (candidate.schema !== "aku.source-candidate-identity.v1" || candidate.authorityRepository !== "AkuBrowser") {
      throw new Error("unsupported schema or authorityRepository");
    }
    requireKeys(candidate.components, ["akuBridge", "akuSidecar"], "components");
    const { akuBridge, akuSidecar } = candidate.components;
    requireKeys(akuBridge, ["version", "chromeVersion", "runtimeRevision", "focusPolicyRevision", "contractVersion"], "akuBridge");
    requireKeys(akuSidecar, ["version", "runtimeRevision"], "akuSidecar");
    for (const [name, component] of Object.entries(candidate.components)) {
      for (const [key, value] of Object.entries(component)) {
        if (typeof value !== "string" || !value || value.trim() !== value) throw new Error(`${name}.${key} must be a nonempty trimmed string`);
      }
      if (!/^\d+\.\d+\.\d+$/.test(component.version)) throw new Error(`${name}.version must have three numeric parts`);
      if (!/^source-adapters-v[1-9][0-9]*$/.test(component.runtimeRevision)) throw new Error(`${name}.runtimeRevision is invalid`);
    }
    if (!/^\d+\.\d+\.\d+\.\d+$/.test(akuBridge.chromeVersion)) throw new Error("akuBridge.chromeVersion must have four numeric parts");
    if (!/^aku-browser\.bridge\.v[1-9][0-9]*$/.test(akuBridge.contractVersion)) throw new Error("akuBridge.contractVersion is invalid");
    if (akuBridge.runtimeRevision !== akuSidecar.runtimeRevision) throw new Error("component runtime revisions must match");
    return candidate;
  } catch (error) {
    throw new Error(`Invalid source candidate identity: ${error.message}`);
  }
}

export async function verifyRuntimeIdentity(workspaceRoot, options = {}) {
  if (!options || typeof options !== "object" || Array.isArray(options) ||
      Object.keys(options).some((key) => key !== "sourceCandidate") ||
      (Object.hasOwn(options, "sourceCandidate") && typeof options.sourceCandidate !== "boolean")) {
    throw new Error("Invalid identity checker options: only sourceCandidate (boolean) is supported");
  }
  const sourceCandidate = Object.hasOwn(options, "sourceCandidate") && options.sourceCandidate;
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

  const releaseCanonical = identityTuple(release);
  const canonical = sourceCandidate ? identityTuple(await readSourceCandidate(browserRoot)) : releaseCanonical;
  const authority = sourceCandidate ? "AkuBrowser/contracts/source-candidate-identity.json" : "AkuBrowser/release/release-manifest.json";

  compare("release distribution authority", release.distribution?.authorityRepository, "AkuBrowser", mismatches);
  if (!/^source-adapters-v[1-9][0-9]*$/.test(releaseCanonical.runtimeRevision ?? "")) {
    mismatches.push(`release runtime revision: invalid ${JSON.stringify(releaseCanonical.runtimeRevision)}`);
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
  compare("AkuBridge focus policy", capture(bridgeCapabilities, /FOCUS_POLICY_REVISION\s*=\s*"([^"]+)"/, "AkuBridge focus policy", mismatches), canonical.focusPolicyRevision, mismatches);
  compare("AkuSidecar focus policy", capture(sidecarReloadActions, /ExpectedBridgeFocusPolicyRevision\s*=\s*"([^"]+)"/, "AkuSidecar focus policy", mismatches), canonical.focusPolicyRevision, mismatches);
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

  // The retained release contract and examples keep their release authority in
  // both modes. Candidate success never requalifies a historical release tuple.
  requireText("AkuBrowser Bridge contract", bridgeContract, `runtime revision \`${releaseCanonical.runtimeRevision}\``, mismatches);
  requireText("AkuBrowser Bridge contract", bridgeContract, `build id \`${releaseCanonical.buildId}\``, mismatches);
  requireText("AkuBridge README", bridgeReadme, `runtime **\`${canonical.runtimeRevision}\`**`, mismatches);
  requireText("AkuSidecar README", sidecarReadme, `AkuBridge \`${canonical.productVersion}\` / \`${canonical.runtimeRevision}\``, mismatches);

  for (const file of [
    "native-runtime-ensure-request.json",
    "native-runtime-invalid-arbitrary-action.json",
    "native-runtime-v1-ensure-request.json",
  ]) {
    const example = (await readJson(path.join(browserRoot, "contracts", "examples", file))).extension;
    compare(`${file} product version`, example.productVersion, releaseCanonical.productVersion, mismatches);
    compare(`${file} runtime revision`, example.runtimeRevision, releaseCanonical.runtimeRevision, mismatches);
    compare(`${file} Bridge contract`, example.bridgeContractVersion, releaseCanonical.contractVersion, mismatches);
  }
  for (const file of ["native-runtime-ready-response.json", "native-runtime-v1-ready-response.json"]) {
    const runtime = (await readJson(path.join(browserRoot, "contracts", "examples", file))).runtime;
    compare(`${file} Sidecar version`, runtime.version, releaseCanonical.sidecarVersion, mismatches);
    compare(`${file} Sidecar runtime revision`, runtime.runtimeRevision, releaseCanonical.sidecarRuntimeRevision, mismatches);
    compare(`${file} Bridge contract`, runtime.bridgeContractVersion, releaseCanonical.contractVersion, mismatches);
  }

  if (mismatches.length > 0) {
    throw new Error([
      "Runtime identity contract mismatch.",
      `Canonical authority: ${authority} (${canonical.buildId})`,
      ...mismatches.map((message) => `- ${message}`),
    ].join("\n"));
  }

  return {
    status: "ok",
    authority,
    productVersion: canonical.productVersion,
    chromeVersion: canonical.chromeVersion,
    runtimeRevision: canonical.runtimeRevision,
    buildId: canonical.buildId,
    contractVersion: canonical.contractVersion,
    scope: sourceCandidate ? "source-candidate-only" : "development-and-release-only",
    runtimeDependency: false,
    ...(sourceCandidate ? {
      referenceAuthority: "AkuBrowser/release/release-manifest.json",
      referenceRuntimeRevision: releaseCanonical.runtimeRevision,
      releaseQualified: false,
    } : {}),
  };
}

async function main() {
  const usage = "usage: node scripts/check-runtime-identity.mjs [workspace-root] [--source-candidate]";
  let root;
  let sourceCandidate = false;
  for (const argument of process.argv.slice(2)) {
    if (argument === "--source-candidate" && !sourceCandidate) sourceCandidate = true;
    else if (argument.startsWith("-") || root !== undefined) throw new Error(usage);
    else root = argument;
  }
  const workspaceRoot = path.resolve(root ?? path.join(scriptDirectory, "..", ".."));
  const result = await verifyRuntimeIdentity(workspaceRoot, { sourceCandidate });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
