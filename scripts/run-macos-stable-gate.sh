#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run-macos-stable-gate.sh [options]

Required:
  --release-version <version>       Top-level AkuBrowser release version
  --sidecar-version <version>       AkuSidecar version and GitHub release tag
  --browser-sha <full SHA>
  --bridge-sha <full SHA>
  --sidecar-sha <full SHA>
  --update-public-key <base64>      Ed25519 public key pinned into the host
  --update-signing-private-key <path>
                                    Ed25519 private-key file used to sign the feed

Optional:
  --version <version>               Backward-compatible alias for --release-version
  --output-root <path>              Fresh artifact directory
EOF
}

die() { echo "error: $*" >&2; exit 1; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$browser_root/.." && pwd)"
bridge_root="$workspace_root/AkuBridge"
sidecar_root="$workspace_root/AkuSidecar"
release_version=""
sidecar_version=""
browser_sha=""
bridge_sha=""
sidecar_sha=""
update_public_key=""
update_signing_private_key=""
candidate_output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-version|--version) release_version="$2"; shift 2 ;;
    --sidecar-version) sidecar_version="$2"; shift 2 ;;
    --browser-sha) browser_sha="$2"; shift 2 ;;
    --bridge-sha) bridge_sha="$2"; shift 2 ;;
    --sidecar-sha) sidecar_sha="$2"; shift 2 ;;
    --update-public-key) update_public_key="$2"; shift 2 ;;
    --update-signing-private-key) update_signing_private_key="$2"; shift 2 ;;
    --output-root) candidate_output="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$(uname -s)" = "Darwin" ]] || die "run this gate on macOS"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--release-version must be a stable semantic version"
[[ "$sidecar_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--sidecar-version must be a stable semantic version"
[[ -n "$update_public_key" ]] || die "--update-public-key is required so the stable host and feed share one trust root"
[[ -f "$update_signing_private_key" ]] || die "--update-signing-private-key must name an existing private-key file"
for sha in "$browser_sha" "$bridge_sha" "$sidecar_sha"; do
  [[ "$sha" =~ ^[a-f0-9]{40}$ ]] || die "all frozen source SHAs must be full lowercase commit IDs"
done

[[ "$(git -C "$browser_root" rev-parse HEAD)" = "$browser_sha" ]] || die "AkuBrowser HEAD differs from the frozen tuple"
[[ "$(git -C "$bridge_root" rev-parse HEAD)" = "$bridge_sha" ]] || die "AkuBridge HEAD differs from the frozen tuple"
[[ "$(git -C "$sidecar_root" rev-parse HEAD)" = "$sidecar_sha" ]] || die "AkuSidecar HEAD differs from the frozen tuple"
for repository in "$browser_root" "$bridge_root" "$sidecar_root"; do
  [[ -z "$(git -C "$repository" status --porcelain)" ]] || die "release source is dirty: $repository"
done

node --input-type=module - "$browser_root/release/release-manifest.json" "$release_version" "$sidecar_version" <<'NODE'
import fs from "node:fs";
const [manifestPath, releaseVersion, sidecarVersion] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (release.version !== releaseVersion || release.components?.akuSidecar?.version !== sidecarVersion || release.channel !== "stable") {
  throw new Error("release manifest must match the stable AkuBrowser and AkuSidecar versions");
}
if (release.distribution?.chromeStore?.nativeRuntimeInstallers?.["macos-universal"]?.trustState !== "unsigned") {
  throw new Error("macOS trust state differs from the unsigned stable build mode");
}
NODE

candidate_output="${candidate_output:-$browser_root/artifacts/stable-${sidecar_version}-macos}"
mkdir -p "$candidate_output"
[[ -z "$(find "$candidate_output" -mindepth 1 -print -quit)" ]] || die "output directory must be empty: $candidate_output"
candidate_output="$(cd "$candidate_output" && pwd)"
c2pa_tool="$sidecar_root/runtime/dev/macos-universal/c2patool"

"$browser_root/scripts/build-macos-preview.sh" --architecture universal --output-root "$candidate_output"
"$browser_root/scripts/test-macos-preview.sh" --zip "$candidate_output/AkuBrowser-${release_version}-macos-universal.zip"
"$browser_root/scripts/build-macos-runtime-installer.sh" \
  --output-root "$candidate_output" \
  --c2pa-tool "$c2pa_tool" \
  --update-public-key "$update_public_key" \
  --update-signing-private-key "$update_signing_private_key" \
  --unsigned-stable-candidate
"$browser_root/scripts/test-macos-runtime-installer.sh" \
  "$candidate_output/AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal.pkg"

(
  cd "$candidate_output"
  shasum -a 256 -c "AkuBrowser-${release_version}-macos-universal.zip.sha256"
  shasum -a 256 -c "AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal.pkg.sha256"
  shasum -a 256 -c "AkuBrowserRuntimeSetup.pkg.sha256"
  shasum -a 256 -c "AkuSidecar-${sidecar_version}-macos-universal.zip.sha256"
)

node --input-type=module - \
  "$candidate_output" "$release_version" "$sidecar_version" "$browser_sha" "$bridge_sha" "$sidecar_sha" \
  "$browser_root/release/release-manifest.json" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [outputRoot, releaseVersion, sidecarVersion, browserSha, bridgeSha, sidecarSha, releasePath] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
const artifactManifest = JSON.parse(fs.readFileSync(path.join(
  outputRoot,
  `AkuBrowser-${releaseVersion}-macos-universal`,
  "artifact-manifest.json",
), "utf8"));
const expected = { akuBrowser: browserSha, akuBridge: bridgeSha, akuSidecar: sidecarSha };
for (const [name, sha] of Object.entries(expected)) {
  if (artifactManifest.sourceCommits?.[name] !== sha) throw new Error(`artifact source mismatch: ${name}`);
}
if ((artifactManifest.sourceDirty ?? []).length !== 0) throw new Error("artifact records dirty release sources");

const names = [
  `AkuBrowser-${releaseVersion}-macos-universal.zip`,
  `AkuBrowser-${releaseVersion}-macos-universal.zip.sha256`,
  `AkuBrowserRuntimeSetup-${sidecarVersion}-macos-universal.pkg`,
  `AkuBrowserRuntimeSetup-${sidecarVersion}-macos-universal.pkg.sha256`,
  "AkuBrowserRuntimeSetup.pkg",
  "AkuBrowserRuntimeSetup.pkg.sha256",
  `AkuSidecar-${sidecarVersion}-macos-universal.zip`,
  `AkuSidecar-${sidecarVersion}-macos-universal.zip.sha256`,
  "AkuSidecarUpdate-macos-universal.json",
];
const emitLegacyV1 = release.version === release.components?.akuBridge?.version
  && release.version === release.components?.akuSidecar?.version
  && release.components?.akuBridge?.runtimeRevision === release.components?.akuSidecar?.runtimeRevision;
if (emitLegacyV1) {
  names.push(
    `AkuBrowserRuntime-${releaseVersion}-macos-universal.zip`,
    `AkuBrowserRuntime-${releaseVersion}-macos-universal.zip.sha256`,
    "AkuBrowserRuntimeUpdate-macos-universal.json",
  );
}
const assets = names.map((name) => {
  const bytes = fs.readFileSync(path.join(outputRoot, name));
  return { name, size: bytes.length, sha256: crypto.createHash("sha256").update(bytes).digest("hex") };
});
console.log(JSON.stringify({
  status: "ok",
  releaseVersion,
  sidecarVersion,
  releaseTag: `v${sidecarVersion}`,
  outputRoot,
  sourceCommits: expected,
  assets,
}, null, 2));
NODE
