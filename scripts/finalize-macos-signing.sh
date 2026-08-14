#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/finalize-macos-signing.sh [options]

Required:
  --request <zip>                    Original Mac signing-request ZIP
  --assets-root <directory>          Original Mac publish assets
  --signed-root <directory>          Windows-signed manifests and receipt
  --update-public-key <base64>        Pinned Ed25519 public key
  --output-root <directory>           Fresh finalized Mac release-kit directory
EOF
}

die() { echo "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
request_zip=""
assets_root=""
signed_root=""
update_public_key=""
output_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) request_zip="$2"; shift 2 ;;
    --assets-root) assets_root="$2"; shift 2 ;;
    --signed-root) signed_root="$2"; shift 2 ;;
    --update-public-key) update_public_key="$2"; shift 2 ;;
    --output-root) output_root="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -f "$request_zip" ]] || die "signing request ZIP is missing"
[[ -d "$assets_root" ]] || die "Mac publish asset directory is missing"
[[ -d "$signed_root" ]] || die "Windows signed output directory is missing"
[[ -n "$update_public_key" ]] || die "--update-public-key is required"

if [[ -d "$signed_root/publish" && -z "$(find "$signed_root" -maxdepth 1 -type f -name '*-macos-signing-receipt.json' -print -quit)" ]]; then
  signed_root="$signed_root/publish"
fi

for command_name in go node shasum unzip zip; do require_command "$command_name"; done
node --input-type=module - "$update_public_key" <<'NODE'
const value = process.argv[2];
if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value) || Buffer.from(value, "base64").length !== 32) {
  throw new Error("--update-public-key must be a base64 32-byte Ed25519 public key");
}
NODE

if [[ -z "$output_root" ]]; then
  output_root="$browser_root/artifacts/stable-macos-final"
fi
mkdir -p "$output_root"
[[ -z "$(find "$output_root" -mindepth 1 -print -quit)" ]] || die "output directory must be new or empty: $output_root"
output_root="$(cd "$output_root" && pwd)"

inspect_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-macos-finalize.XXXXXX")"
trap 'rm -rf -- "$inspect_root"' EXIT
unzip -q "$request_zip" -d "$inspect_root/request"
request_root="$inspect_root/request"
request_metadata="$request_root/signing-request.json"
[[ -f "$request_metadata" ]] || die "signing request metadata is missing"

"$browser_root/scripts/test-macos-signing-request.sh" \
  --request "$request_zip" \
  --assets-root "$assets_root" \
  --public-key "$update_public_key"

node --input-type=module - "$request_metadata" "$signed_root" "$request_zip" "$update_public_key" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [requestPath, signedRoot, requestZip, publicKey] = process.argv.slice(2);
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const safeName = (value, label) => {
  if (typeof value !== "string" || value.length === 0 || value !== path.basename(value) || value.includes("\\")) {
    throw new Error(`${label} must be a single relative filename: ${value}`);
  }
  return value;
};
const request = readJson(requestPath);
const receiptFiles = fs.readdirSync(signedRoot).filter((name) => name.endsWith("-macos-signing-receipt.json"));
if (receiptFiles.length !== 1) throw new Error("exactly one Windows signing receipt is required");
const receiptPath = path.join(signedRoot, receiptFiles[0]);
const receipt = readJson(receiptPath);
if (receipt.schemaVersion !== 1 || receipt.kind !== "AkuBrowser.macos-signing-receipt" || receipt.status !== "signed") throw new Error("signing receipt identity is invalid");
if (receipt.requestArchive !== path.basename(requestZip) || receipt.requestSha256 !== sha256(requestZip)) throw new Error("signing receipt is not bound to this request ZIP");
if (receipt.releaseVersion !== request.releaseVersion || receipt.sidecarVersion !== request.sidecarVersion || receipt.releaseTag !== request.releaseTag) throw new Error("signing receipt release identity differs from request");
if (JSON.stringify(receipt.sourceCommits) !== JSON.stringify(request.sourceCommits)) throw new Error("signing receipt source tuple differs from request");
if (JSON.stringify(receipt.toolingCommits) !== JSON.stringify(request.toolingCommits)) throw new Error("signing receipt tooling tuple differs from request");
if (receipt.publicKey?.base64 !== publicKey || receipt.publicKey?.keyId !== "aku-runtime-stable-v1" || receipt.publicKey?.algorithm !== "Ed25519") throw new Error("signing receipt public key differs from request");
if ((receipt.assetRecords ?? []).length !== (request.publishAssets ?? []).length) throw new Error("signing receipt asset count differs from request");
for (const expectedAsset of request.publishAssets) {
  const expectedName = safeName(expectedAsset.name, "request asset name");
  const actualAsset = receipt.assetRecords.find((candidate) => candidate.name === expectedName);
  if (!actualAsset || actualAsset.bytes !== expectedAsset.bytes || actualAsset.sha256 !== expectedAsset.sha256) throw new Error(`signing receipt asset binding differs from request: ${expectedName}`);
}
if ((receipt.signedManifests ?? []).length !== (request.unsignedManifests ?? []).length) throw new Error("signing receipt manifest count differs from request");
const seenManifestKeys = new Set();
for (const item of receipt.signedManifests) {
  const outputName = safeName(item.outputName, "receipt signed manifest name");
  const inputName = safeName(item.inputName, "receipt unsigned manifest name");
  const artifactName = safeName(item.artifactName, "receipt artifact name");
  const expected = request.unsignedManifests.find((candidate) => candidate.outputName === outputName && candidate.inputName === inputName);
  if (!expected) throw new Error(`receipt contains an unexpected manifest: ${outputName}`);
  const manifestKey = `${inputName}\u0000${outputName}`;
  if (seenManifestKeys.has(manifestKey)) throw new Error(`receipt contains a duplicate manifest: ${outputName}`);
  seenManifestKeys.add(manifestKey);
  if (artifactName !== expected.artifactName) throw new Error(`signed manifest binding differs from request: ${outputName}`);
  const signedPath = path.join(signedRoot, outputName);
  if (!fs.existsSync(signedPath)) throw new Error(`signed manifest is missing: ${outputName}`);
  if (sha256(signedPath) !== item.signedSha256) throw new Error(`signed manifest digest differs from receipt: ${outputName}`);
  if (item.unsignedSha256 !== expected.sha256) throw new Error(`signed manifest binding differs from request: ${outputName}`);
}
if (seenManifestKeys.size !== request.unsignedManifests.length) throw new Error("signing receipt does not cover every requested manifest");
NODE

receipt_path="$(find "$signed_root" -maxdepth 1 -type f -name '*-macos-signing-receipt.json' -print -quit)"
[[ -f "$receipt_path" ]] || die "signing receipt path could not be resolved"

mkdir -p "$output_root/publish"
cp "$signed_root/"*-macos-signing-receipt.json "$output_root/publish/"

node --input-type=module - "$request_metadata" "$assets_root" "$output_root/publish" <<'NODE'
import fs from "node:fs";
import path from "node:path";
const [requestPath, assetsRoot, outputRoot] = process.argv.slice(2);
const request = JSON.parse(fs.readFileSync(requestPath, "utf8"));
const safeName = (value) => {
  if (typeof value !== "string" || value.length === 0 || value !== path.basename(value) || value.includes("\\")) throw new Error(`invalid publish asset name: ${value}`);
  return value;
};
for (const item of request.publishAssets ?? []) {
  const name = safeName(item.name);
  const source = path.join(assetsRoot, name);
  const destination = path.join(outputRoot, name);
  if (!fs.existsSync(source)) throw new Error(`publish asset is missing: ${name}`);
  fs.copyFileSync(source, destination);
}
NODE

node --input-type=module - "$request_metadata" "$request_root" "$assets_root" "$signed_root" "$output_root/publish" "$update_public_key" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [requestPath, requestRoot, assetsRoot, signedRoot, outputRoot, publicKey] = process.argv.slice(2);
const request = JSON.parse(fs.readFileSync(requestPath, "utf8"));
const safeName = (value, label) => {
  if (typeof value !== "string" || value.length === 0 || value !== path.basename(value) || value.includes("\\")) {
    throw new Error(`${label} must be a single relative filename: ${value}`);
  }
  return value;
};
const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  return value;
};
for (const item of request.unsignedManifests) {
  const inputName = safeName(item.inputName, "unsigned manifest input name");
  const outputName = safeName(item.outputName, "signed manifest output name");
  const expectedArtifactName = safeName(item.artifactName, "unsigned manifest artifact name");
  const unsigned = JSON.parse(fs.readFileSync(path.join(requestRoot, inputName), "utf8"));
  const signed = JSON.parse(fs.readFileSync(path.join(signedRoot, outputName), "utf8"));
  const { signature, ...signedUnsigned } = signed;
  if (!signature || JSON.stringify(stable(unsigned)) !== JSON.stringify(stable(signedUnsigned))) throw new Error(`signed manifest payload changed: ${outputName}`);
  if (signed.signature.algorithm !== "ed25519" || signed.signature.keyId !== "aku-runtime-stable-v1") throw new Error(`signed manifest identity is invalid: ${outputName}`);
  const artifactName = path.basename(signed.artifact?.url ?? "");
  if (artifactName !== expectedArtifactName) throw new Error(`signed manifest artifact name changed: ${outputName}`);
  const artifactPath = path.join(assetsRoot, artifactName);
  if (!fs.existsSync(artifactPath) || signed.artifact.size !== fs.statSync(artifactPath).size || signed.artifact.sha256 !== sha256(artifactPath)) throw new Error(`signed artifact binding is invalid: ${outputName}`);
  fs.copyFileSync(path.join(signedRoot, outputName), path.join(outputRoot, outputName));
}
const receipt = fs.readdirSync(outputRoot).find((name) => name.endsWith("-macos-signing-receipt.json"));
if (!receipt) throw new Error("final release kit has no signing receipt");
NODE

public_key="$update_public_key"
for manifest in "$output_root/publish/AkuSidecarUpdate-macos-universal.json" "$output_root/publish/AkuBrowserRuntimeUpdate-macos-universal.json"; do
  [[ -f "$manifest" ]] || continue
  (cd "$browser_root/installer/windows" && go run -buildvcs=false ./cmd/sign-update-manifest -verify-signed "$manifest" -public-key "$public_key")
done

release_version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).version)' "$output_root/publish/release-manifest.json")"
sidecar_version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).components.akuSidecar.version)' "$output_root/publish/release-manifest.json")"
receipt_name="$(basename "$receipt_path")"

node --input-type=module - "$output_root/release-kit.json" "$output_root" "$release_version" "$sidecar_version" "$request_metadata" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [destination, outputRoot, releaseVersion, sidecarVersion, requestPath] = process.argv.slice(2);
const request = JSON.parse(fs.readFileSync(requestPath, "utf8"));
const publishRoot = path.join(outputRoot, "publish");
const publishAssets = fs.readdirSync(publishRoot).filter((name) => fs.statSync(path.join(publishRoot, name)).isFile()).sort().map((name) => {
  const file = path.join(publishRoot, name);
  return { path: `publish/${name}`, bytes: fs.statSync(file).size, sha256: crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex") };
});
if (publishAssets.some((item) => item.path.includes(".unsigned."))) throw new Error("final kit contains an unsigned manifest");
if (!publishAssets.some((item) => item.path.endsWith("-macos-signing-receipt.json"))) throw new Error("final kit is missing the signing receipt");
const kit = {
  schemaVersion: 1,
  status: "ok",
  releaseVersion,
  sidecarVersion,
  releaseTag: `v${sidecarVersion}`,
  sourceCommits: request.sourceCommits,
  toolingCommits: request.toolingCommits,
  signing: { macosInstaller: "unsigned", updateManifests: "ed25519", privateKeyLocation: "windows-only" },
  publishAssets,
};
fs.writeFileSync(destination, `${JSON.stringify(kit, null, 2)}\n`);
NODE

node --input-type=module - "$output_root/README.md" "$release_version" <<'NODE'
import fs from "node:fs";
const [destination, releaseVersion] = process.argv.slice(2);
fs.writeFileSync(destination, `# AkuBrowser finalized macOS release kit ${releaseVersion}\n\nThe publish lane contains the unsigned Mac package/binaries, Windows-signed update manifests, and signing receipt. The private key remained on Windows.\n`);
NODE

echo "macOS finalized release kit: $output_root"
