#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

for command_name in node python3 shasum unzip; do
  require_command "$command_name"
done

node_bin="$(command -v node)"
python_bin="$(command -v python3)"
unzip_bin="$(command -v unzip)"

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_manifest_path="$browser_root/release/release-manifest.json"
bridge_identity_registry_path="$browser_root/config/bridge-identities.json"
artifact_directory=""
zip_path=""

usage() {
  cat <<'EOF'
Usage: ./scripts/test-macos-preview.sh [options]

Options:
  --artifact-directory <path>  Test an extracted bundle
  --zip <path>                 Extract and test a bundle ZIP
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-directory)
      [[ $# -ge 2 ]] || die "--artifact-directory requires a value"
      artifact_directory="$2"
      shift 2
      ;;
    --zip)
      [[ $# -ge 2 ]] || die "--zip requires a value"
      zip_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -z "$artifact_directory" || -z "$zip_path" ]] || die "choose either --artifact-directory or --zip"
if [[ -z "$artifact_directory" && -z "$zip_path" ]]; then
  version="$($node_bin --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).version)' "$release_manifest_path")"
  architecture="$(uname -m)"
  case "$architecture" in
    x86_64) architecture="x64" ;;
    arm64|aarch64) architecture="arm64" ;;
    *) die "unsupported macOS host architecture: $(uname -m)" ;;
  esac
  artifact_directory="$browser_root/artifacts/AkuBrowser-${version}-macos-${architecture}"
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-macos-test.XXXXXX")"
cleanup() {
  if [[ -n "${sidecar_pid:-}" ]] && kill -0 "$sidecar_pid" 2>/dev/null; then
    kill -TERM "$sidecar_pid" 2>/dev/null || true
    wait "$sidecar_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp_root"
}
trap cleanup EXIT

if [[ -n "$zip_path" ]]; then
  [[ -f "$zip_path" ]] || die "ZIP does not exist: $zip_path"
  "$unzip_bin" -q "$zip_path" -d "$tmp_root/extracted"
  artifact_directory="$(find "$tmp_root/extracted" -name release-manifest.json -type f -print -quit | sed 's#/release-manifest.json$##')"
fi

artifact_directory="$(cd "$artifact_directory" && pwd)"
[[ -f "$artifact_directory/release-manifest.json" ]] || die "bundle is missing release-manifest.json"
[[ -f "$artifact_directory/artifact-manifest.json" ]] || die "bundle is missing artifact-manifest.json"
[[ -f "$artifact_directory/checksums.sha256" ]] || die "bundle is missing checksums.sha256"
[[ -x "$artifact_directory/AkuSidecar" ]] || die "bundle is missing executable AkuSidecar"
[[ -f "$artifact_directory/AkuBridge/manifest.json" ]] || die "bundle is missing AkuBridge/manifest.json"
[[ -f "$artifact_directory/config/sidecar.json" ]] || die "bundle is missing config/sidecar.json"
[[ -x "$artifact_directory/Start-AkuBrowser.sh" ]] || die "bundle is missing executable Start-AkuBrowser.sh"
[[ -x "$artifact_directory/Start-AkuBrowser.command" ]] || die "bundle is missing executable Start-AkuBrowser.command"
[[ -f "$artifact_directory/README.md" ]] || die "bundle is missing README.md"

while IFS= read -r line; do
  hash="${line%%  *}"
  relative="${line#*  }"
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || die "invalid checksum line: $line"
  [[ "$relative" != /* && "$relative" != *".."* ]] || die "unsafe checksum path: $relative"
  file="$artifact_directory/$relative"
  [[ -f "$file" ]] || die "checksummed file is missing: $relative"
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual" == "$hash" ]] || die "checksum mismatch: $relative"
done < "$artifact_directory/checksums.sha256"

target="$($node_bin --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).target)' "$artifact_directory/artifact-manifest.json")"
[[ "$target" == macos-* ]] || die "artifact target is not macOS: $target"

"$node_bin" --input-type=module - "$release_manifest_path" "$bridge_identity_registry_path" "$artifact_directory" <<'NODE'
import fs from "node:fs";

const [releasePath, registryPath, artifactDirectory] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const artifactRelease = JSON.parse(fs.readFileSync(`${artifactDirectory}/release-manifest.json`, "utf8"));
const artifactManifest = JSON.parse(fs.readFileSync(`${artifactDirectory}/artifact-manifest.json`, "utf8"));
const bridgeManifest = JSON.parse(fs.readFileSync(`${artifactDirectory}/AkuBridge/manifest.json`, "utf8"));
const packageConfig = JSON.parse(fs.readFileSync(`${artifactDirectory}/config/sidecar.json`, "utf8"));
const readme = fs.readFileSync(`${artifactDirectory}/README.md`, "utf8");
const fail = (message) => { throw new Error(message); };

const bridgeIdentityProfile = release.distribution?.chromeStore?.bridgeIdentityProfile;
const bridgeIdentity = registry.profiles?.[bridgeIdentityProfile];
if (registry.schemaVersion !== 1 || !bridgeIdentityProfile || !bridgeIdentity) {
  fail("the release does not select a valid Bridge identity profile");
}
if (bridgeIdentity.distribution !== "chrome-web-store") fail("the release Bridge identity is not a Chrome Web Store profile");
if (!/^[a-p]{32}$/.test(bridgeIdentity.extensionId ?? "")) fail("the release Bridge extension ID is invalid");
const bridgeExtensionOrigin = `chrome-extension://${bridgeIdentity.extensionId}/`;
if (artifactRelease.version !== release.version) fail("artifact release version differs from AkuBrowser");
if (bridgeManifest.version_name !== release.components?.akuBridge?.version) fail("bundled AkuBridge product version differs from the release tuple");
if (bridgeManifest.version !== release.components?.akuBridge?.chromeVersion) fail("bundled AkuBridge Chrome version differs from the release tuple");
const trustedOrigins = packageConfig.bridge?.trustedExtensionOrigins ?? [];
if (trustedOrigins.length !== 1 || trustedOrigins[0] !== bridgeExtensionOrigin) {
  fail("packaged AkuSidecar does not trust exactly the release-selected Bridge origin");
}
if (artifactManifest.bridgeIdentity?.profile !== bridgeIdentityProfile) fail("artifact provenance records the wrong Bridge identity profile");
if (artifactManifest.bridgeIdentity?.distribution !== bridgeIdentity.distribution) fail("artifact provenance records the wrong Bridge distribution");
if (artifactManifest.bridgeIdentity?.authority !== "config/bridge-identities.json") fail("artifact provenance does not record the Bridge identity authority");
if (artifactManifest.bridgeIdentity?.extensionOrigin !== bridgeExtensionOrigin) fail("artifact provenance records the wrong Bridge extension origin");
const bridgeInstallInstruction = readme.indexOf("Install **AkuBrowser** from the Chrome Web Store");
const launcherInstruction = readme.indexOf("./Start-AkuBrowser.sh");
if (bridgeInstallInstruction < 0) fail("bundle README does not explain how to install AkuBrowser from the Chrome Web Store");
if (launcherInstruction < 0) fail("bundle README does not identify Start-AkuBrowser.sh as the launcher");
if (bridgeInstallInstruction >= launcherInstruction) fail("bundle README must install the Chrome Web Store extension before starting AkuBrowser");
if (!readme.includes("Do not load it unpacked")) fail("bundle README does not prevent loading the inspection copy of AkuBridge unpacked");
NODE

port="$($python_bin -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
output_log="$tmp_root/sidecar.log"
"$artifact_directory/Start-AkuBrowser.sh" \
  --provider deterministic \
  --no-open \
  --data-directory "$tmp_root/data" \
  --port "$port" > "$output_log" 2>&1 &
sidecar_pid=$!

health=""
for _ in $(seq 1 80); do
  if ! kill -0 "$sidecar_pid" 2>/dev/null; then
    cat "$output_log" >&2
    die "AkuSidecar exited during startup"
  fi
  health="$(/usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${port}/api/health" 2>/dev/null || true)"
  if [[ -n "$health" ]]; then break; fi
  sleep 0.25
done
[[ -n "$health" ]] || { cat "$output_log" >&2; die "AkuSidecar did not become healthy"; }

localhost_health="$(/usr/bin/curl -fsS --max-time 5 "http://localhost:${port}/api/health" 2>/dev/null || true)"
[[ -n "$localhost_health" ]] || die "AkuSidecar did not serve the localhost alias"

"$node_bin" --input-type=module - "$health" "$artifact_directory" "$port" <<'NODE'
import fs from "node:fs";
const [healthText, artifactDirectory, port] = process.argv.slice(2);
const health = JSON.parse(healthText);
const release = JSON.parse(fs.readFileSync(`${artifactDirectory}/release-manifest.json`, "utf8"));
if (health.status !== "ok") throw new Error("health status is not ok");
if (health.version !== release.version) throw new Error(`health version ${health.version} differs from release ${release.version}`);
if (health.runtime !== "go") throw new Error("health runtime is not go");
if (health.provider !== "deterministic") throw new Error("smoke provider is not deterministic");
console.log(JSON.stringify({ status: "ok", version: health.version, runtime: health.runtime, provider: health.provider, port }, null, 2));
NODE

bootstrap="$(/usr/bin/curl -fsS --max-time 5 "http://127.0.0.1:${port}/api/bootstrap")"
"$node_bin" --input-type=module - "$bootstrap" <<'NODE'
const bootstrap = JSON.parse(process.argv[2]);
if (bootstrap.settings?.loadProfile !== "standard") throw new Error("fresh database is not Standard 1x");
if (bootstrap.settings?.aiDetectionPresentation !== "drawer") throw new Error("fresh database is not Drawer AI presentation");
console.log(JSON.stringify({ status: "ok", loadProfile: bootstrap.settings.loadProfile, aiDetectionPresentation: bootstrap.settings.aiDetectionPresentation }, null, 2));
NODE

ui_status="$(/usr/bin/curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${port}/")"
[[ "$ui_status" == "200" ]] || die "embedded AkuBrowser UI returned HTTP $ui_status"

kill -TERM "$sidecar_pid"
wait "$sidecar_pid" || true
sidecar_pid=""
echo "macOS preview smoke test passed: $artifact_directory"
