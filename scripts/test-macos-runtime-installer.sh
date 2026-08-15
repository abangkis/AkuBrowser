#!/usr/bin/env bash
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./scripts/test-macos-runtime-installer.sh [options] [package]

Options:
  --bridge-identity-profile <name>  Expected identity profile (default: release profile)
  -h, --help                        Show this help
EOF
}

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_manifest="$browser_root/release/release-manifest.json"
bridge_identity_registry="$browser_root/config/bridge-identities.json"
version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).version)' "$release_manifest")"
sidecar_version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).components.akuSidecar.version)' "$release_manifest")"
emit_legacy_v1="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.version === r.components?.akuBridge?.version && r.version === r.components?.akuSidecar?.version && r.components?.akuBridge?.runtimeRevision === r.components?.akuSidecar?.runtimeRevision ? "1" : "0")' "$release_manifest")"
bridge_identity_profile=""
package_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bridge-identity-profile) bridge_identity_profile="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) [[ -z "$package_path" ]] || die "only one installer package may be supplied"; package_path="$1"; shift ;;
  esac
done

release_bridge_identity_profile="$(node --input-type=module -e '
  import fs from "node:fs";
  console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).distribution?.chromeStore?.bridgeIdentityProfile ?? "");
' "$release_manifest")"
bridge_identity_profile="${bridge_identity_profile:-$release_bridge_identity_profile}"
extension_id="$(node --input-type=module -e '
  import fs from "node:fs";
  const [registryPath, profile] = process.argv.slice(1);
  const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  const identity = registry.profiles?.[profile];
  if (registry.schemaVersion !== 2 || !profile || !identity || !/^[a-p]{32}$/.test(identity.extensionId ?? "")) {
    throw new Error("expected Bridge identity profile is invalid");
  }
  console.log(identity.extensionId);
' "$bridge_identity_registry" "$bridge_identity_profile")"
package_path="${package_path:-$browser_root/artifacts/AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal-unsigned-local.pkg}"
[[ -f "$package_path" ]] || die "installer package is missing: $package_path"
package_directory="$(cd "$(dirname "$package_path")" && pwd)"

inspect_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-pkg-test.XXXXXX")"
trap 'rm -rf -- "$inspect_root"' EXIT
pkgutil --expand-full "$package_path" "$inspect_root/expanded"

distribution="$inspect_root/expanded/Distribution"
component="$inspect_root/expanded/AkuBrowserRuntime.pkg"
payload="$component/Payload/Library/Application Support/AkuBrowser"
postinstall="$component/Scripts/postinstall"
preinstall="$component/Scripts/preinstall"
host="$payload/host/AkuBrowserRuntimeHost"
sidecar="$payload/runtime/versions/$sidecar_version/AkuSidecar"
c2pa_tool="$payload/runtime/versions/$sidecar_version/c2patool"
current="$payload/runtime/current.json"
sidecar_config="$payload/runtime/versions/$sidecar_version/config/sidecar.json"

for required in "$distribution" "$preinstall" "$postinstall" "$host" "$sidecar" "$current" "$sidecar_config" "$payload/Uninstall-AkuBrowserRuntime.command"; do
  [[ -f "$required" ]] || die "package payload is missing: $required"
done

node --input-type=module - "$sidecar_config" "$bridge_identity_profile" "$sidecar_version" <<'NODE'
import fs from "node:fs";
const [file, profile, version] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(file, "utf8"));
const expectedMode = profile === "acceptance" ? "acceptance" : profile;
if (config.deployment?.mode !== expectedMode || config.deployment?.runtimeInstallKind !== "installed" ||
    config.deployment?.bridgeIdentityProfile !== profile || config.deployment?.releaseVersion !== version) {
  throw new Error("installed runtime deployment provenance is invalid");
}
NODE
grep -q 'enable_currentUserHome="true"' "$distribution" || die "package is not current-user scoped"
grep -q 'enable_localSystem="false"' "$distribution" || die "package unexpectedly permits system installation"
grep -q "runtime/versions/$sidecar_version/AkuSidecar" "$postinstall" || die "postinstall version drifted"
grep -Fq 'data/.runtime-version' "$postinstall" || die "postinstall does not record the runtime data writer version"
grep -Fq 'pre-downgrade-' "$preinstall" || die "preinstall does not archive newer downgrade data"
grep -Fq "$sidecar_version" "$preinstall" || die "preinstall target version drifted"
grep -Fq "chrome-extension://$extension_id/" "$postinstall" || die "expected $bridge_identity_profile extension origin is missing"
if [[ "$bridge_identity_profile" = "acceptance" ]]; then
  production_extension_id="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).profiles["production-store"].extensionId)' "$bridge_identity_registry")"
  ! grep -Fq "chrome-extension://$production_extension_id/" "$postinstall" || die "acceptance package also permits the production extension origin"
fi
grep -q 'Google/Chrome/NativeMessagingHosts' "$postinstall" || die "Chrome Native Messaging registration is missing"
grep -Fq -- '--preserve-data' "$payload/Uninstall-AkuBrowserRuntime.command" || die "macOS uninstaller lacks preserve-data mode"
grep -Fq -- '--full-reset' "$payload/Uninstall-AkuBrowserRuntime.command" || die "macOS uninstaller lacks full-reset mode"

for executable in "$host" "$sidecar"; do
  architectures="$(lipo -archs "$executable")"
  [[ "$architectures" == *x86_64* && "$architectures" == *arm64* ]] || die "binary is not universal: $executable ($architectures)"
done

if [[ -f "$c2pa_tool" ]]; then
  expected_c2pa_sha256="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.components.c2paTool.platformSha256["macos-universal"])' "$release_manifest")"
  expected_c2pa_version="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.components.c2paTool.version)' "$release_manifest")"
  c2pa_architectures="$(lipo -archs "$c2pa_tool")"
  [[ "$c2pa_architectures" == *x86_64* && "$c2pa_architectures" == *arm64* ]] || die "packaged c2patool is not universal: $c2pa_architectures"
  [[ "$(shasum -a 256 "$c2pa_tool" | awk '{print $1}')" = "$expected_c2pa_sha256" ]] || die "packaged c2patool differs from the release pin"
  [[ "$("$c2pa_tool" --version)" = "c2patool $expected_c2pa_version" ]] || die "packaged c2patool version differs from the release manifest"
fi

node --input-type=module - "$current" "$sidecar_version" <<'NODE'
import fs from "node:fs";
const [file, version] = process.argv.slice(2);
const current = JSON.parse(fs.readFileSync(file, "utf8"));
if (current.schemaVersion !== 1 || !["stable", "preview"].includes(current.channel) || current.version !== version) {
  throw new Error("installed runtime metadata is invalid");
}
if (current.bridgeContractVersion !== "aku-browser.bridge.v2") {
  throw new Error("installed Bridge contract is invalid");
}
NODE

unsigned_package=0
if ! pkgutil --check-signature "$package_path" >/dev/null; then
  unsigned_package=1
  [[ "$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.distribution.chromeStore.nativeRuntimeInstallers["macos-universal"].trustState)' "$release_manifest")" = "unsigned" ]] || die "unsigned package is not declared by the release manifest"
fi

if [[ "$unsigned_package" -eq 1 && ( "$bridge_identity_profile" != "acceptance" || "$(basename "$package_path")" != *-unsigned-local.pkg ) ]]; then
  unsigned_welcome="$inspect_root/expanded/Resources/welcome.html"
  [[ -f "$unsigned_welcome" ]] || die "unsigned package is missing its welcome disclosure"
  tr '\n' ' ' < "$unsigned_welcome" | tr -s '[:space:]' ' ' | grep -Eq 'not( |</strong>) .*signed|not Developer ID-signed or notarized' || die "unsigned package does not identify its trust state"
  grep -q 'Open Anyway' "$unsigned_welcome" || die "unsigned package does not provide bounded Gatekeeper guidance"
fi

sidecar_update_artifact="$package_directory/AkuSidecar-${sidecar_version}-macos-universal.zip"
sidecar_update_manifest="$package_directory/AkuSidecarUpdate-macos-universal.json"
legacy_update_artifact="$package_directory/AkuBrowserRuntime-${version}-macos-universal.zip"
legacy_update_manifest="$package_directory/AkuBrowserRuntimeUpdate-macos-universal.json"
if [[ -f "$sidecar_update_manifest" || -f "$legacy_update_manifest" ]]; then
  [[ -f "$sidecar_update_artifact" && -f "$sidecar_update_manifest" ]] || die "AkuSidecar v2 update artifact and manifest must be produced together"
  if [[ "$emit_legacy_v1" -eq 1 ]]; then
    [[ -f "$legacy_update_artifact" && -f "$legacy_update_manifest" ]] || die "aligned releases must retain the legacy v1 update feed during transition"
  else
    [[ ! -f "$legacy_update_artifact" && ! -f "$legacy_update_manifest" ]] || die "independent component releases must not emit an invalid legacy v1 feed"
  fi
  node --input-type=module - "$sidecar_update_artifact" "$sidecar_update_manifest" "$legacy_update_artifact" "$legacy_update_manifest" "$sidecar_version" "$version" "$emit_legacy_v1" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [sidecarArtifactPath, sidecarManifestPath, legacyArtifactPath, legacyManifestPath, sidecarVersion, releaseVersion, emitLegacyV1] = process.argv.slice(2);
const verifyArtifact = (artifactPath, manifest) => {
  const artifact = fs.readFileSync(artifactPath);
  if (manifest.artifact.size !== artifact.length || manifest.artifact.sha256 !== crypto.createHash("sha256").update(artifact).digest("hex")) throw new Error("update artifact digest is invalid");
  if (manifest.signature?.algorithm !== "ed25519" || manifest.signature?.keyId !== "aku-runtime-stable-v1" || manifest.signature?.value?.length !== 88) throw new Error("update signature metadata is invalid");
};
const sidecarManifest = JSON.parse(fs.readFileSync(sidecarManifestPath, "utf8"));
const expectedSidecarName = `AkuSidecar-${sidecarVersion}-macos-universal.zip`;
if (sidecarManifest.schemaVersion !== 2 || sidecarManifest.product !== "AkuSidecar" || sidecarManifest.channel !== "stable") throw new Error("AkuSidecar update manifest identity is invalid");
if (sidecarManifest.sidecarVersion !== sidecarVersion || sidecarManifest.artifact.platform !== "macos-universal" || !sidecarManifest.artifact.url.endsWith(`/v${sidecarVersion}/${expectedSidecarName}`)) throw new Error("AkuSidecar update artifact URL is invalid");
if (sidecarManifest.bridgeCompatibility?.protocol !== "aku-browser.bridge" || sidecarManifest.databaseCompatibility?.maxSchemaVersion < sidecarManifest.databaseCompatibility?.minSchemaVersion) throw new Error("AkuSidecar compatibility metadata is invalid");
verifyArtifact(sidecarArtifactPath, sidecarManifest);
if (emitLegacyV1 === "1") {
  const legacyManifest = JSON.parse(fs.readFileSync(legacyManifestPath, "utf8"));
  const expectedLegacyName = `AkuBrowserRuntime-${releaseVersion}-macos-universal.zip`;
  if (legacyManifest.schemaVersion !== 1 || legacyManifest.product !== "AkuBrowser" || legacyManifest.version !== releaseVersion || !legacyManifest.artifact.url.endsWith(`/v${releaseVersion}/${expectedLegacyName}`)) throw new Error("legacy update manifest is invalid");
  verifyArtifact(legacyArtifactPath, legacyManifest);
}
NODE
  mkdir -p "$inspect_root/update"
  ditto -x -k "$sidecar_update_artifact" "$inspect_root/update"
  lipo -archs "$inspect_root/update/AkuSidecar" | grep -q x86_64 || die "update Sidecar lacks x86_64"
  lipo -archs "$inspect_root/update/AkuSidecar" | grep -q arm64 || die "update Sidecar lacks arm64"
  node --input-type=module - "$inspect_root/update" "$sidecar_version" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [root, version] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(path.join(root, "payload-manifest.json"), "utf8"));
if (manifest.version !== version || manifest.architecture !== "macos-universal") throw new Error("runtime payload identity is invalid");
for (const item of manifest.files) {
  const data = fs.readFileSync(path.join(root, ...item.path.split("/")));
  if (data.length !== item.size || crypto.createHash("sha256").update(data).digest("hex") !== item.sha256) throw new Error(`runtime payload drifted: ${item.path}`);
}
NODE
  verify_checksum() {
    local checksum="$1"
    local expected_checksum actual_checksum
    [[ -f "$checksum" ]] || die "update checksum is missing: $checksum"
    [[ "$(awk '{print $2}' "$checksum")" = "$(basename "${checksum%.sha256}")" ]] || die "update checksum must use a portable basename: $checksum"
    expected_checksum="$(awk '{print $1}' "$checksum")"
    actual_checksum="$(shasum -a 256 "${checksum%.sha256}" | awk '{print $1}')"
    [[ "$expected_checksum" = "$actual_checksum" ]] || die "update checksum does not match artifact: $checksum"
  }
  verify_checksum "$sidecar_update_artifact.sha256"
  [[ "$emit_legacy_v1" -eq 0 ]] || verify_checksum "$legacy_update_artifact.sha256"
fi

sidecar_unsigned_manifest="$package_directory/AkuSidecarUpdate-macos-universal.unsigned.json"
legacy_unsigned_manifest="$package_directory/AkuBrowserRuntimeUpdate-macos-universal.unsigned.json"
if [[ -f "$sidecar_unsigned_manifest" || -f "$legacy_unsigned_manifest" ]]; then
  [[ ! -f "$sidecar_update_manifest" && ! -f "$legacy_update_manifest" ]] || die "unsigned and signed update manifests must not coexist in the Mac producer output"
  [[ -f "$sidecar_update_artifact" && -f "$sidecar_unsigned_manifest" ]] || die "AkuSidecar v2 unsigned artifact and manifest must be produced together"
  if [[ "$emit_legacy_v1" -eq 1 ]]; then
    [[ -f "$legacy_update_artifact" && -f "$legacy_unsigned_manifest" ]] || die "aligned releases must retain the unsigned legacy v1 request manifest"
  else
    [[ ! -f "$legacy_update_artifact" && ! -f "$legacy_unsigned_manifest" ]] || die "independent component releases must not emit an invalid unsigned legacy v1 feed"
  fi
  node --input-type=module - "$sidecar_update_artifact" "$sidecar_unsigned_manifest" "$legacy_update_artifact" "$legacy_unsigned_manifest" "$sidecar_version" "$version" "$emit_legacy_v1" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [sidecarArtifactPath, sidecarManifestPath, legacyArtifactPath, legacyManifestPath, sidecarVersion, releaseVersion, emitLegacyV1] = process.argv.slice(2);
const verifyUnsigned = (artifactPath, manifestPath, expectedSchema, expectedProduct, expectedVersion, expectedName, expectedTag) => {
  const artifact = fs.readFileSync(artifactPath);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (Object.hasOwn(manifest, "signature")) throw new Error(`unsigned manifest contains a signature: ${path.basename(manifestPath)}`);
  if (manifest.schemaVersion !== expectedSchema || manifest.product !== expectedProduct || manifest.channel !== "stable") throw new Error(`unsigned manifest identity is invalid: ${path.basename(manifestPath)}`);
  if ((manifest.sidecarVersion ?? manifest.version) !== expectedVersion || !manifest.artifact.url.endsWith(`/v${expectedTag}/${expectedName}`)) throw new Error(`unsigned manifest URL or version is invalid: ${path.basename(manifestPath)}`);
  if (manifest.artifact.size !== artifact.length || manifest.artifact.sha256 !== crypto.createHash("sha256").update(artifact).digest("hex")) throw new Error(`unsigned artifact digest is invalid: ${path.basename(manifestPath)}`);
};
verifyUnsigned(sidecarArtifactPath, sidecarManifestPath, 2, "AkuSidecar", sidecarVersion, `AkuSidecar-${sidecarVersion}-macos-universal.zip`, sidecarVersion);
if (emitLegacyV1 === "1") verifyUnsigned(legacyArtifactPath, legacyManifestPath, 1, "AkuBrowser", releaseVersion, `AkuBrowserRuntime-${releaseVersion}-macos-universal.zip`, releaseVersion);
NODE
fi
echo "macOS runtime installer structural test passed: $package_path"
