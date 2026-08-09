#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run-macos-stable-gate.sh [options]

Required:
  --version <version>
  --browser-sha <full SHA>
  --bridge-sha <full SHA>
  --sidecar-sha <full SHA>

Optional:
  --output-root <path>  Fresh artifact directory
EOF
}

die() { echo "error: $*" >&2; exit 1; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$browser_root/.." && pwd)"
bridge_root="$workspace_root/AkuBridge"
sidecar_root="$workspace_root/AkuSidecar"
release_version=""
browser_sha=""
bridge_sha=""
sidecar_sha=""
candidate_output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) release_version="$2"; shift 2 ;;
    --browser-sha) browser_sha="$2"; shift 2 ;;
    --bridge-sha) bridge_sha="$2"; shift 2 ;;
    --sidecar-sha) sidecar_sha="$2"; shift 2 ;;
    --output-root) candidate_output="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$(uname -s)" = "Darwin" ]] || die "run this gate on macOS"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must be a stable semantic version"
for sha in "$browser_sha" "$bridge_sha" "$sidecar_sha"; do
  [[ "$sha" =~ ^[a-f0-9]{40}$ ]] || die "all frozen source SHAs must be full lowercase commit IDs"
done

[[ "$(git -C "$browser_root" rev-parse HEAD)" = "$browser_sha" ]] || die "AkuBrowser HEAD differs from the frozen tuple"
[[ "$(git -C "$bridge_root" rev-parse HEAD)" = "$bridge_sha" ]] || die "AkuBridge HEAD differs from the frozen tuple"
[[ "$(git -C "$sidecar_root" rev-parse HEAD)" = "$sidecar_sha" ]] || die "AkuSidecar HEAD differs from the frozen tuple"
for repository in "$browser_root" "$bridge_root" "$sidecar_root"; do
  [[ -z "$(git -C "$repository" status --porcelain)" ]] || die "release source is dirty: $repository"
done

node --input-type=module - "$browser_root/release/release-manifest.json" "$release_version" <<'NODE'
import fs from "node:fs";
const [manifestPath, version] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (release.version !== version || release.channel !== "stable") {
  throw new Error("release manifest must match the stable version");
}
if (release.distribution?.chromeStore?.nativeRuntimeInstallers?.["macos-universal"]?.trustState !== "unsigned") {
  throw new Error("macOS trust state differs from the unsigned stable build mode");
}
NODE

candidate_output="${candidate_output:-$browser_root/artifacts/stable-${release_version}-macos}"
mkdir -p "$candidate_output"
[[ -z "$(find "$candidate_output" -mindepth 1 -print -quit)" ]] || die "output directory must be empty: $candidate_output"
candidate_output="$(cd "$candidate_output" && pwd)"
c2pa_tool="$sidecar_root/runtime/dev/macos-universal/c2patool"

"$browser_root/scripts/build-macos-preview.sh" --architecture universal --output-root "$candidate_output"
"$browser_root/scripts/test-macos-preview.sh" --zip "$candidate_output/AkuBrowser-${release_version}-macos-universal.zip"
"$browser_root/scripts/build-macos-runtime-installer.sh" \
  --output-root "$candidate_output" \
  --c2pa-tool "$c2pa_tool" \
  --unsigned-stable-candidate
"$browser_root/scripts/test-macos-runtime-installer.sh" \
  "$candidate_output/AkuBrowserRuntimeSetup-${release_version}-macos-universal.pkg"

(
  cd "$candidate_output"
  shasum -a 256 -c "AkuBrowser-${release_version}-macos-universal.zip.sha256"
  shasum -a 256 -c "AkuBrowserRuntimeSetup-${release_version}-macos-universal.pkg.sha256"
  shasum -a 256 -c "AkuBrowserRuntimeSetup.pkg.sha256"
)

node --input-type=module - \
  "$candidate_output" "$release_version" "$browser_sha" "$bridge_sha" "$sidecar_sha" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [outputRoot, version, browserSha, bridgeSha, sidecarSha] = process.argv.slice(2);
const artifactManifest = JSON.parse(fs.readFileSync(path.join(
  outputRoot,
  `AkuBrowser-${version}-macos-universal`,
  "artifact-manifest.json",
), "utf8"));
const expected = { akuBrowser: browserSha, akuBridge: bridgeSha, akuSidecar: sidecarSha };
for (const [name, sha] of Object.entries(expected)) {
  if (artifactManifest.sourceCommits?.[name] !== sha) throw new Error(`artifact source mismatch: ${name}`);
}
if ((artifactManifest.sourceDirty ?? []).length !== 0) throw new Error("artifact records dirty release sources");

const names = [
  `AkuBrowser-${version}-macos-universal.zip`,
  `AkuBrowser-${version}-macos-universal.zip.sha256`,
  `AkuBrowserRuntimeSetup-${version}-macos-universal.pkg`,
  `AkuBrowserRuntimeSetup-${version}-macos-universal.pkg.sha256`,
  "AkuBrowserRuntimeSetup.pkg",
  "AkuBrowserRuntimeSetup.pkg.sha256",
];
const assets = names.map((name) => {
  const bytes = fs.readFileSync(path.join(outputRoot, name));
  return { name, size: bytes.length, sha256: crypto.createHash("sha256").update(bytes).digest("hex") };
});
console.log(JSON.stringify({ status: "ok", version, outputRoot, sourceCommits: expected, assets }, null, 2));
NODE
