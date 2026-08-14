#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/test-macos-signing-request.sh --request <zip> --assets-root <directory> --public-key <base64>
EOF
}

die() { echo "error: $*" >&2; exit 1; }

request_zip=""
assets_root=""
public_key=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) request_zip="$2"; shift 2 ;;
    --assets-root) assets_root="$2"; shift 2 ;;
    --public-key) public_key="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -f "$request_zip" ]] || die "signing request ZIP is missing: $request_zip"
[[ -d "$assets_root" ]] || die "publish asset directory is missing: $assets_root"
[[ -n "$public_key" ]] || die "--public-key is required"

for command_name in unzip node shasum; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is unavailable: $command_name"
done

inspect_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-macos-signing-request-test.XXXXXX")"
trap 'rm -rf -- "$inspect_root"' EXIT
unzip -q "$request_zip" -d "$inspect_root/request"

[[ -f "$inspect_root/request/signing-request.json" ]] || die "signing request metadata is missing"
[[ -f "$inspect_root/request/release-manifest.json" ]] || die "release manifest is missing from signing request"
[[ -f "$inspect_root/request/portable-artifact-manifest.json" ]] || die "portable artifact manifest is missing from signing request"

if find "$inspect_root/request" -type f \( -name '*.dpapi' -o -name '*.key' -o -name '*private*' -o -name '*secret*' \) -print -quit | grep -q .; then
  die "signing request contains a private-key-like file"
fi

node --input-type=module - "$inspect_root/request" "$assets_root" "$public_key" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [requestRoot, assetsRoot, expectedPublicKey] = process.argv.slice(2);
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const fail = (message) => { throw new Error(message); };
const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const safeName = (value, label) => {
  if (typeof value !== "string" || value.length === 0 || value !== path.basename(value) || value.includes("\\")) {
    fail(`${label} must be a single relative filename: ${value}`);
  }
  return value;
};
const record = (file) => ({
  bytes: fs.statSync(file).size,
  sha256: sha256(file),
});

const request = readJson(path.join(requestRoot, "signing-request.json"));
if (request.schemaVersion !== 1 || request.kind !== "AkuBrowser.macos-signing-request" || request.status !== "unsigned") {
  fail("signing request identity is invalid");
}
if (!/^\d+\.\d+\.\d+$/.test(request.releaseVersion) || !/^\d+\.\d+\.\d+$/.test(request.sidecarVersion)) {
  fail("signing request versions are invalid");
}
for (const [name, sha] of Object.entries(request.sourceCommits ?? {})) {
  if (!/^[a-f0-9]{40}$/.test(sha)) fail(`source commit is invalid: ${name}`);
}
if (request.publicKey?.algorithm !== "Ed25519" || request.publicKey?.keyId !== "aku-runtime-stable-v1" ||
    request.publicKey?.base64 !== expectedPublicKey || Buffer.from(expectedPublicKey, "base64").length !== 32) {
  fail("signing request public key metadata is invalid");
}

const assets = new Map();
for (const item of request.publishAssets ?? []) {
  const name = safeName(item.name, "publish asset name");
  if (assets.has(name)) fail(`duplicate publish asset: ${name}`);
  const file = path.join(assetsRoot, name);
  if (!fs.existsSync(file)) fail(`publish asset is missing: ${item.name}`);
  const actual = record(file);
  if (actual.bytes !== item.bytes || actual.sha256 !== item.sha256) fail(`publish asset digest mismatch: ${name}`);
  assets.set(name, { file, ...actual });
}

const portableManifest = readJson(path.join(requestRoot, "portable-artifact-manifest.json"));
if (portableManifest.sourceCommits?.akuBrowser !== request.sourceCommits.akuBrowser ||
    portableManifest.sourceCommits?.akuBridge !== request.sourceCommits.akuBridge ||
    portableManifest.sourceCommits?.akuSidecar !== request.sourceCommits.akuSidecar ||
    (portableManifest.sourceDirty ?? []).length !== 0) {
  fail("portable artifact provenance does not match the frozen source tuple");
}

for (const item of request.unsignedManifests ?? []) {
  const inputName = safeName(item.inputName, "unsigned manifest input name");
  const outputName = safeName(item.outputName, "signed manifest output name");
  const artifactNameFromRequest = safeName(item.artifactName, "unsigned manifest artifact name");
  const file = path.join(requestRoot, inputName);
  if (!fs.existsSync(file)) fail(`unsigned manifest is missing: ${inputName}`);
  const actual = record(file);
  if (actual.bytes !== item.bytes || actual.sha256 !== item.sha256) fail(`unsigned manifest digest mismatch: ${inputName}`);
  const manifest = readJson(file);
  if (Object.hasOwn(manifest, "signature")) fail(`unsigned manifest contains a signature: ${inputName}`);
  const artifactName = path.basename(manifest.artifact?.url ?? "");
  const artifact = assets.get(artifactName);
  if (!artifact || manifest.artifact.size !== artifact.bytes || manifest.artifact.sha256 !== artifact.sha256) {
    fail(`unsigned manifest artifact binding is invalid: ${inputName}`);
  }
  const expectedTag = manifest.schemaVersion === 2 ? request.sidecarVersion : request.releaseVersion;
  if (!manifest.artifact.url.endsWith(`/releases/download/v${expectedTag}/${artifactName}`)) {
    fail(`unsigned manifest artifact URL is not pinned to the immutable release tag: ${inputName}`);
  }
  if (artifactName !== artifactNameFromRequest || manifest.schemaVersion !== item.schemaVersion || outputName !== inputName.replace(/\.unsigned\.json$/, ".json")) {
    fail(`unsigned manifest output mapping is invalid: ${inputName}`);
  }
}
if ((request.unsignedManifests ?? []).length === 0) fail("signing request contains no unsigned manifests");
NODE

echo "macOS signing request passed: $request_zip"
