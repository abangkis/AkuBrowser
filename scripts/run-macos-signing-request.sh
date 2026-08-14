#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run-macos-signing-request.sh [options]

Required:
  --release-version <version>       Top-level AkuBrowser release version
  --sidecar-version <version>       AkuSidecar version and GitHub release tag
  --browser-sha <full SHA>
  --browser-tooling-sha <full SHA>   AkuBrowser commit containing approved release tooling
  --bridge-sha <full SHA>
  --sidecar-sha <full SHA>
  --update-public-key <base64>      Ed25519 public key pinned into the host

Optional:
  --output-root <path>              Fresh Mac handoff kit directory
  --c2pa-tool <path>                Universal c2patool binary
EOF
}

die() { echo "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$browser_root/.." && pwd)"
bridge_root="$workspace_root/AkuBridge"
sidecar_root="$workspace_root/AkuSidecar"
release_manifest="$browser_root/release/release-manifest.json"

release_version=""
sidecar_version=""
browser_sha=""
browser_tooling_sha=""
bridge_sha=""
sidecar_sha=""
update_public_key=""
output_root=""
c2pa_tool=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-version) release_version="$2"; shift 2 ;;
    --sidecar-version) sidecar_version="$2"; shift 2 ;;
    --browser-sha) browser_sha="$2"; shift 2 ;;
    --browser-tooling-sha) browser_tooling_sha="$2"; shift 2 ;;
    --bridge-sha) bridge_sha="$2"; shift 2 ;;
    --sidecar-sha) sidecar_sha="$2"; shift 2 ;;
    --update-public-key) update_public_key="$2"; shift 2 ;;
    --output-root) output_root="$2"; shift 2 ;;
    --c2pa-tool) c2pa_tool="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$(uname -s)" = "Darwin" ]] || die "run the macOS signing-request producer on macOS"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--release-version must be a stable semantic version"
[[ "$sidecar_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--sidecar-version must be a stable semantic version"
for sha in "$browser_sha" "$browser_tooling_sha" "$bridge_sha" "$sidecar_sha"; do
  [[ "$sha" =~ ^[a-f0-9]{40}$ ]] || die "all frozen source SHAs must be full lowercase commit IDs"
done
[[ -n "$update_public_key" ]] || die "--update-public-key is required"

for command_name in git node shasum zip; do require_command "$command_name"; done
[[ -d "$bridge_root" ]] || die "AkuBridge checkout is missing: $bridge_root"
[[ -d "$sidecar_root" ]] || die "AkuSidecar checkout is missing: $sidecar_root"

node --input-type=module - "$update_public_key" <<'NODE'
const value = process.argv[2];
const decoded = Buffer.from(value, "base64");
if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value) || decoded.length !== 32) {
  throw new Error("--update-public-key must be a base64 32-byte Ed25519 public key");
}
NODE

node --input-type=module - "$release_manifest" "$release_version" "$sidecar_version" <<'NODE'
import fs from "node:fs";
const [manifestPath, releaseVersion, sidecarVersion] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (release.version !== releaseVersion || release.components?.akuSidecar?.version !== sidecarVersion || release.channel !== "stable") {
  throw new Error("release manifest does not match the frozen stable versions");
}
if (release.distribution?.chromeStore?.nativeRuntimeInstallers?.["macos-universal"]?.trustState !== "unsigned") {
  throw new Error("macOS stable candidate must declare unsigned trust state");
}
NODE
emit_legacy_v1="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.version === r.components?.akuBridge?.version && r.version === r.components?.akuSidecar?.version && r.components?.akuBridge?.runtimeRevision === r.components?.akuSidecar?.runtimeRevision ? "1" : "0")' "$release_manifest")"

[[ -z "$(git -C "$browser_root" status --porcelain)" ]] || die "release tooling source is dirty: $browser_root"
tooling_drift_json="$(node "$browser_root/scripts/verify-release-tooling-drift.mjs" "$browser_root" "$browser_sha" "$browser_tooling_sha")"

for repository_and_sha in \
  "$bridge_root:$bridge_sha" \
  "$sidecar_root:$sidecar_sha"; do
  repository="${repository_and_sha%:*}"
  expected="${repository_and_sha##*:}"
  [[ "$(git -C "$repository" rev-parse HEAD)" = "$expected" ]] || die "frozen SHA differs at $repository"
  [[ -z "$(git -C "$repository" status --porcelain)" ]] || die "release source is dirty: $repository"
done

c2pa_tool="${c2pa_tool:-$sidecar_root/runtime/dev/macos-universal/c2patool}"
[[ -f "$c2pa_tool" ]] || die "universal c2patool is missing: $c2pa_tool"

if [[ -z "$output_root" ]]; then
  output_root="$browser_root/artifacts/stable-${sidecar_version}-macos"
fi
mkdir -p "$output_root"
[[ -z "$(find "$output_root" -mindepth 1 -print -quit)" ]] || die "output directory must be new or empty: $output_root"
output_root="$(cd "$output_root" && pwd)"

stage_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-macos-signing-request.XXXXXX")"
cleanup() { rm -rf -- "$stage_root"; }
trap cleanup EXIT

preview_root="$stage_root/preview"
installer_root="$stage_root/installer"
publish_root="$stage_root/publish"
request_root="$stage_root/request"
mkdir -p "$publish_root" "$request_root"
printf '%s\n' "$tooling_drift_json" > "$request_root/browser-tooling-drift.json"

"$browser_root/scripts/build-macos-preview.sh" \
  --architecture universal \
  --output-root "$preview_root" \
  --release-browser-sha "$browser_sha" \
  --browser-tooling-sha "$browser_tooling_sha"
"$browser_root/scripts/test-macos-preview.sh" \
  --zip "$preview_root/AkuBrowser-${release_version}-macos-universal.zip"

"$browser_root/scripts/build-macos-runtime-installer.sh" \
  --output-root "$installer_root" \
  --c2pa-tool "$c2pa_tool" \
  --update-public-key "$update_public_key" \
  --unsigned-stable-candidate \
  --emit-unsigned-update-manifests
"$browser_root/scripts/test-macos-runtime-installer.sh" \
  "$installer_root/AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal.pkg"

copy_asset() {
  local source="$1"
  local destination="$2"
  [[ -f "$source" ]] || die "required Mac asset is missing: $source"
  cp "$source" "$destination"
}

copy_asset "$preview_root/AkuBrowser-${release_version}-macos-universal.zip" "$publish_root/"
copy_asset "$preview_root/AkuBrowser-${release_version}-macos-universal.zip.sha256" "$publish_root/"
copy_asset "$installer_root/AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal.pkg" "$publish_root/"
copy_asset "$installer_root/AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal.pkg.sha256" "$publish_root/"
copy_asset "$installer_root/AkuBrowserRuntimeSetup.pkg" "$publish_root/"
copy_asset "$installer_root/AkuBrowserRuntimeSetup.pkg.sha256" "$publish_root/"
copy_asset "$installer_root/AkuSidecar-${sidecar_version}-macos-universal.zip" "$publish_root/"
copy_asset "$installer_root/AkuSidecar-${sidecar_version}-macos-universal.zip.sha256" "$publish_root/"
if [[ "$emit_legacy_v1" -eq 1 ]]; then
  copy_asset "$installer_root/AkuBrowserRuntime-${release_version}-macos-universal.zip" "$publish_root/"
  copy_asset "$installer_root/AkuBrowserRuntime-${release_version}-macos-universal.zip.sha256" "$publish_root/"
fi
copy_asset "$release_manifest" "$publish_root/release-manifest.json"

copy_asset "$installer_root/AkuSidecarUpdate-macos-universal.unsigned.json" "$request_root/"
if [[ "$emit_legacy_v1" -eq 1 ]]; then
  copy_asset "$installer_root/AkuBrowserRuntimeUpdate-macos-universal.unsigned.json" "$request_root/"
fi
copy_asset "$release_manifest" "$request_root/release-manifest.json"
copy_asset "$preview_root/AkuBrowser-${release_version}-macos-universal/artifact-manifest.json" "$request_root/portable-artifact-manifest.json"

node --input-type=module - "$request_root/signing-request.json" "$request_root" "$publish_root" "$release_version" "$sidecar_version" "$emit_legacy_v1" "$browser_sha" "$browser_tooling_sha" "$bridge_sha" "$sidecar_sha" "$update_public_key" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [destination, requestRoot, publishRoot, releaseVersion, sidecarVersion, emitLegacyV1, browserSha, browserToolingSha, bridgeSha, sidecarSha, publicKey] = process.argv.slice(2);
const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const record = (name) => {
  const file = path.join(publishRoot, name);
  return { name, bytes: fs.statSync(file).size, sha256: sha256(file) };
};
const release = JSON.parse(fs.readFileSync(path.join(requestRoot, "release-manifest.json"), "utf8"));
const publishNames = [
  `AkuBrowser-${releaseVersion}-macos-universal.zip`,
  `AkuBrowser-${releaseVersion}-macos-universal.zip.sha256`,
  `AkuBrowserRuntimeSetup-${sidecarVersion}-macos-universal.pkg`,
  `AkuBrowserRuntimeSetup-${sidecarVersion}-macos-universal.pkg.sha256`,
  "AkuBrowserRuntimeSetup.pkg",
  "AkuBrowserRuntimeSetup.pkg.sha256",
  `AkuSidecar-${sidecarVersion}-macos-universal.zip`,
  `AkuSidecar-${sidecarVersion}-macos-universal.zip.sha256`,
  "release-manifest.json",
];
if (emitLegacyV1 === "1") {
  publishNames.splice(-1, 0,
    `AkuBrowserRuntime-${releaseVersion}-macos-universal.zip`,
    `AkuBrowserRuntime-${releaseVersion}-macos-universal.zip.sha256`,
  );
}
const publishAssets = publishNames.map(record);
const unsignedNames = [`AkuSidecarUpdate-macos-universal.unsigned.json`];
if (emitLegacyV1 === "1") unsignedNames.push("AkuBrowserRuntimeUpdate-macos-universal.unsigned.json");
const assets = new Map(publishAssets.map((item) => [item.name, item]));
const unsignedManifests = unsignedNames.map((inputName) => {
  const file = path.join(requestRoot, inputName);
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  if (Object.hasOwn(manifest, "signature")) throw new Error(`manifest is not unsigned: ${inputName}`);
  const artifactName = path.basename(manifest.artifact?.url ?? "");
  const artifact = assets.get(artifactName);
  if (!artifact || manifest.artifact.size !== artifact.bytes || manifest.artifact.sha256 !== artifact.sha256) {
    throw new Error(`manifest artifact binding is invalid: ${inputName}`);
  }
  return {
    inputName,
    outputName: inputName.replace(/\.unsigned\.json$/, ".json"),
    schemaVersion: manifest.schemaVersion,
    bytes: fs.statSync(file).size,
    sha256: sha256(file),
    artifactName,
    artifactBytes: artifact.bytes,
    artifactSha256: artifact.sha256,
  };
});
const portable = JSON.parse(fs.readFileSync(path.join(requestRoot, "portable-artifact-manifest.json"), "utf8"));
const toolingDriftPath = path.join(requestRoot, "browser-tooling-drift.json");
const toolingDrift = JSON.parse(fs.readFileSync(toolingDriftPath, "utf8"));
if (toolingDrift.releaseSourceSha !== browserSha || toolingDrift.toolingSha !== browserToolingSha || toolingDrift.status !== "ok") {
  throw new Error("AkuBrowser release/tooling provenance is invalid");
}
const request = {
  schemaVersion: 1,
  kind: "AkuBrowser.macos-signing-request",
  status: "unsigned",
  releaseVersion,
  sidecarVersion,
  releaseTag: `v${sidecarVersion}`,
  sourceCommits: { akuBrowser: browserSha, akuBridge: bridgeSha, akuSidecar: sidecarSha },
  toolingCommits: { akuBrowser: browserToolingSha },
  publicKey: { algorithm: "Ed25519", keyId: "aku-runtime-stable-v1", base64: publicKey },
  publishAssets,
  unsignedManifests,
  provenance: {
    portableArtifactManifestSha256: sha256(path.join(requestRoot, "portable-artifact-manifest.json")),
    browserToolingDriftSha256: sha256(toolingDriftPath),
    portableSourceCommits: portable.sourceCommits,
  },
};
fs.writeFileSync(destination, `${JSON.stringify(request, null, 2)}\n`);
NODE

request_archive="AkuBrowser-${release_version}-macos-signing-request.zip"
request_zip="$stage_root/$request_archive"
(cd "$request_root" && zip -q -r "$request_zip" .)
mkdir -p "$output_root/publish" "$output_root/handoff"
cp "$publish_root/"* "$output_root/publish/"
cp "$request_zip" "$output_root/handoff/$request_archive"

"$browser_root/scripts/test-macos-signing-request.sh" \
  --request "$output_root/handoff/$request_archive" \
  --assets-root "$output_root/publish" \
  --public-key "$update_public_key"

node --input-type=module - "$output_root/release-kit.json" "$output_root" "$output_root/publish" "$output_root/handoff" "$release_version" "$sidecar_version" "$browser_sha" "$browser_tooling_sha" "$bridge_sha" "$sidecar_sha" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [destination, outputRoot, publishRoot, handoffRoot, releaseVersion, sidecarVersion, browserSha, browserToolingSha, bridgeSha, sidecarSha] = process.argv.slice(2);
const recordLane = (root) => fs.readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isFile()).sort((a, b) => a.name.localeCompare(b.name)).map((entry) => {
  const file = path.join(root, entry.name);
  return { path: path.relative(outputRoot, file).split(path.sep).join("/"), bytes: fs.statSync(file).size, sha256: crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex") };
});
const kit = {
  schemaVersion: 1,
  status: "awaiting_windows_signing",
  releaseVersion,
  sidecarVersion,
  releaseTag: `v${sidecarVersion}`,
  outputRoot,
  sourceCommits: { akuBrowser: browserSha, akuBridge: bridgeSha, akuSidecar: sidecarSha },
  toolingCommits: { akuBrowser: browserToolingSha },
  signing: { macosInstaller: "unsigned", updateManifests: "windows-finalizer", privateKeyLocation: "windows-only" },
  publishAssets: recordLane(publishRoot),
  handoffAssets: recordLane(handoffRoot),
};
fs.writeFileSync(destination, `${JSON.stringify(kit, null, 2)}\n`);
NODE

node --input-type=module - "$output_root/README.md" "$release_version" <<'NODE'
import fs from "node:fs";
const [destination, releaseVersion] = process.argv.slice(2);
fs.writeFileSync(destination, `# AkuBrowser macOS signing-request kit ${releaseVersion}\n\n* publish/ contains the unsigned Mac binaries and package assets.\n* handoff/ contains the signing request for the Windows signing authority.\n* The private update key must remain on Windows; do not add it to this kit.\n\nAfter Windows signs the manifests, use the Mac finalizer to verify the receipt and produce the final publishable kit.\n`);
NODE

node --input-type=module - "$output_root/release-kit.json" "$output_root/README.md" <<'NODE'
import fs from "node:fs";
const [kitPath, readmePath] = process.argv.slice(2);
const kit = JSON.parse(fs.readFileSync(kitPath, "utf8"));
if (kit.status !== "awaiting_windows_signing" || kit.publishAssets.length === 0 || kit.handoffAssets.length !== 1) throw new Error("invalid macOS signing-request kit");
const text = fs.readFileSync(readmePath, "utf8");
if (text.includes("$(") || /[\x00-\x08\x0B\x0C\x0E-\x1F]/.test(text)) throw new Error("README contains unresolved template text");
NODE

cat "$output_root/release-kit.json"
