#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/build-macos-runtime-installer.sh [options]

Options:
  --output-root <path>                 Artifact directory (default: artifacts)
  --extension-id <id>                  Exact Chrome extension ID (defaults to release manifest)
  --c2pa-tool <path>                   Universal c2patool binary (required for production)
  --application-identity <identity>    Developer ID Application signing identity
  --installer-identity <identity>      Developer ID Installer signing identity
  --notary-profile <profile>           notarytool keychain profile; submit and staple the package
  --update-public-key <base64>         Ed25519 update public key pinned into the native host
  --update-signing-private-key <path>  Base64 Ed25519 seed/private key for the macOS update manifest
  --unsigned-local-candidate           Build an explicitly unsigned local candidate
  --allow-dirty                        Allow dirty source trees for a local candidate
  --skip-validation                    Skip source test suites
  -h, --help                           Show this help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$browser_root/.." && pwd)"
bridge_root="$workspace_root/AkuBridge"
sidecar_root="$workspace_root/AkuSidecar"
release_manifest="$browser_root/release/release-manifest.json"
installer_source="$browser_root/installer/macos"
output_root="$browser_root/artifacts"
extension_id=""
c2pa_tool=""
application_identity=""
installer_identity=""
notary_profile=""
update_public_key=""
update_signing_private_key=""
unsigned_local=0
allow_dirty=0
skip_validation=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-root) output_root="$2"; shift 2 ;;
    --extension-id) extension_id="$2"; shift 2 ;;
    --c2pa-tool) c2pa_tool="$2"; shift 2 ;;
    --application-identity) application_identity="$2"; shift 2 ;;
    --installer-identity) installer_identity="$2"; shift 2 ;;
    --notary-profile) notary_profile="$2"; shift 2 ;;
    --update-public-key) update_public_key="$2"; shift 2 ;;
    --update-signing-private-key) update_signing_private_key="$2"; shift 2 ;;
    --unsigned-local-candidate) unsigned_local=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --skip-validation) skip_validation=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

for command_name in git go node npm lipo pkgbuild productbuild shasum zip; do require_command "$command_name"; done
[[ "$(uname -s)" = "Darwin" ]] || die "the macOS runtime installer must be built on macOS"

version="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.version)' "$release_manifest")"
release_extension_id="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.distribution.chromeStore.extensionId)' "$release_manifest")"
expected_c2pa_sha256="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.components.c2paTool.platformSha256?.["macos-universal"] ?? "")' "$release_manifest")"
expected_c2pa_version="$(node --input-type=module -e 'import fs from "node:fs"; const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(r.components.c2paTool.version)' "$release_manifest")"
extension_id="${extension_id:-$release_extension_id}"
[[ "$extension_id" =~ ^[a-p]{32}$ ]] || die "a real 32-character Chrome Web Store extension ID is required"
if [[ "$unsigned_local" -eq 0 && "$extension_id" != "$release_extension_id" ]]; then
  die "production installer extension ID must match the release manifest"
fi
if [[ "$unsigned_local" -eq 0 ]]; then
  [[ -n "$application_identity" ]] || die "production build requires --application-identity"
  [[ -n "$installer_identity" ]] || die "production build requires --installer-identity"
  [[ -n "$notary_profile" ]] || die "production build requires --notary-profile"
  [[ -n "$c2pa_tool" && -f "$c2pa_tool" ]] || die "production build requires --c2pa-tool"
  [[ -n "$update_public_key" ]] || die "production build requires --update-public-key"
  [[ -n "$update_signing_private_key" && -f "$update_signing_private_key" ]] || die "production build requires --update-signing-private-key"
fi
if [[ -n "$c2pa_tool" ]]; then
  [[ -f "$c2pa_tool" ]] || die "c2patool input is not a file: $c2pa_tool"
  [[ "$expected_c2pa_sha256" =~ ^[a-f0-9]{64}$ ]] || die "release manifest must pin components.c2paTool.platformSha256.macos-universal"
  actual_c2pa_sha256="$(shasum -a 256 "$c2pa_tool" | awk '{print $1}')"
  [[ "$actual_c2pa_sha256" = "$expected_c2pa_sha256" ]] || die "macOS c2patool checksum does not match the release manifest"
  c2pa_architectures="$(lipo -archs "$c2pa_tool" 2>/dev/null || true)"
  [[ "$c2pa_architectures" == *x86_64* && "$c2pa_architectures" == *arm64* ]] || die "c2patool must be universal (x86_64 and arm64)"
  c2pa_version="$($c2pa_tool --version)"
  [[ "$c2pa_version" = "c2patool $expected_c2pa_version" ]] || die "c2patool version differs from the release manifest: $c2pa_version"
fi

if [[ "$allow_dirty" -eq 0 ]]; then
  for repository in "$browser_root" "$bridge_root" "$sidecar_root"; do
    [[ -z "$(git -C "$repository" status --porcelain)" ]] || die "release sources must be clean; use --allow-dirty for a local candidate"
  done
fi

go_cache="${TMPDIR:-/tmp}/akubrowser-go-cache"
go_mod_cache="${TMPDIR:-/tmp}/akubrowser-go-mod-cache"
mkdir -p "$go_cache" "$go_mod_cache"

if [[ "$skip_validation" -eq 0 ]]; then
  (cd "$bridge_root/native-host" && GOCACHE="$go_cache" GOMODCACHE="$go_mod_cache" go test -buildvcs=false ./...)
  (cd "$sidecar_root" && GOCACHE="$go_cache" GOMODCACHE="$go_mod_cache" go test -buildvcs=false -p 1 ./...)
  (cd "$bridge_root" && npm run check)
fi

mkdir -p "$output_root"
output_root="$(cd "$output_root" && pwd)"
suffix=""
[[ "$unsigned_local" -eq 1 ]] && suffix="-unsigned-local"
versioned_package="$output_root/AkuBrowserRuntimeSetup-${version}-macos-universal${suffix}.pkg"
stable_package="$output_root/AkuBrowserRuntimeSetup${suffix}.pkg"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-macos-installer.XXXXXX")"
trap 'rm -rf -- "$build_root"' EXIT
payload_root="$build_root/payload"
component_package="$build_root/AkuBrowserRuntime.pkg"
distribution_file="$build_root/Distribution.xml"
scripts_root="$build_root/scripts"
resources_root="$build_root/resources"
install_root="$payload_root/Library/Application Support/AkuBrowser"
host_root="$install_root/host"
runtime_root="$install_root/runtime"
version_root="$runtime_root/versions/$version"

mkdir -p "$host_root" "$version_root/config" "$version_root/schemas" "$install_root/data" "$scripts_root" "$resources_root"

build_universal_go() {
  local package_root="$1" package_path="$2" output="$3" ldflags="$4"
  (cd "$package_root" && GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 GOCACHE="$go_cache" GOMODCACHE="$go_mod_cache" go build -buildvcs=false -trimpath -ldflags "$ldflags" -o "$build_root/$output-x64" "$package_path")
  (cd "$package_root" && GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 GOCACHE="$go_cache" GOMODCACHE="$go_mod_cache" go build -buildvcs=false -trimpath -ldflags "$ldflags" -o "$build_root/$output-arm64" "$package_path")
  lipo -create "$build_root/$output-x64" "$build_root/$output-arm64" -output "$output"
  chmod 755 "$output"
}

host_ldflags="-s -w"
[[ -z "$update_public_key" ]] || host_ldflags="$host_ldflags -X main.pinnedUpdatePublicKey=$update_public_key"
build_universal_go "$bridge_root/native-host" . "$host_root/AkuBrowserRuntimeHost" "$host_ldflags"
build_universal_go "$sidecar_root" ./cmd/akusidecar "$version_root/AkuSidecar" "-s -w"

node --input-type=module - "$sidecar_root/config/sidecar.json" "$version_root/config/sidecar.json" "$extension_id" <<'NODE'
import fs from "node:fs";
const [source, destination, extensionId] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(source, "utf8"));
config.database.path = "data/aku-browser.db";
config.reasoning.executable = "";
config.bridge.trustedExtensionOrigins = [`chrome-extension://${extensionId}/`];
fs.writeFileSync(destination, `${JSON.stringify(config, null, 2)}\n`);
NODE
cp "$sidecar_root"/schemas/*.schema.json "$version_root/schemas/"
if [[ -n "$c2pa_tool" ]]; then
  cp "$c2pa_tool" "$version_root/c2patool"
  chmod 755 "$version_root/c2patool"
fi

runtime_channel="stable"
[[ "$unsigned_local" -eq 0 ]] || runtime_channel="preview"
node --input-type=module - "$runtime_root/current.json" "$version" "$bridge_root/bridge-capabilities.js" "$runtime_channel" <<'NODE'
import fs from "node:fs";
const [destination, version, capabilitiesPath, channel] = process.argv.slice(2);
const source = fs.readFileSync(capabilitiesPath, "utf8");
const revision = source.match(/BRIDGE_RUNTIME_REVISION\s*=\s*["']([^"']+)/)?.[1];
if (!revision) throw new Error("Bridge runtime revision is unavailable");
fs.writeFileSync(destination, `${JSON.stringify({
  schemaVersion: 1,
  channel,
  version,
  runtimeRevision: revision,
  bridgeContractVersion: "aku-browser.bridge.v2",
  rollbackVersion: null,
}, null, 2)}\n`);
NODE

cp "$installer_source/Uninstall-AkuBrowserRuntime.command" "$install_root/Uninstall-AkuBrowserRuntime.command"
chmod 755 "$install_root/Uninstall-AkuBrowserRuntime.command"
sed -e "s/@VERSION@/$version/g" -e "s/@EXTENSION_ID@/$extension_id/g" "$installer_source/scripts/postinstall" > "$scripts_root/postinstall"
chmod 755 "$scripts_root/postinstall"
cp "$installer_source/resources/"*.html "$resources_root/"
sed "s/@VERSION@/$version/g" "$installer_source/Distribution.xml" > "$distribution_file"

if [[ -n "$application_identity" ]]; then
  codesign --force --options runtime --timestamp --sign "$application_identity" "$host_root/AkuBrowserRuntimeHost"
  codesign --force --options runtime --timestamp --sign "$application_identity" "$version_root/AkuSidecar"
  [[ ! -f "$version_root/c2patool" ]] || codesign --force --options runtime --timestamp --sign "$application_identity" "$version_root/c2patool"
fi

if [[ -n "$update_signing_private_key" ]]; then
  update_payload="$build_root/update-payload"
  update_artifact="$output_root/AkuBrowserRuntime-${version}-macos-universal.zip"
  update_manifest="$output_root/AkuBrowserRuntimeUpdate-macos-universal.json"
  unsigned_update_manifest="$build_root/runtime-update-unsigned.json"
  rm -f -- "$update_artifact" "$update_artifact.sha256" "$update_manifest"
  mkdir -p "$update_payload"
  cp -R "$version_root/". "$update_payload/"
  node --input-type=module - "$update_payload" "$version" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [root, version] = process.argv.slice(2);
const files = [];
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(absolute);
    else if (entry.isFile()) {
      const data = fs.readFileSync(absolute);
      files.push({
        path: path.relative(root, absolute).split(path.sep).join("/"),
        size: data.length,
        sha256: crypto.createHash("sha256").update(data).digest("hex"),
      });
    }
  }
}
walk(root);
files.sort((left, right) => left.path.localeCompare(right.path));
fs.writeFileSync(path.join(root, "payload-manifest.json"), `${JSON.stringify({
  schemaVersion: 1,
  product: "AkuBrowser",
  version,
  architecture: "macos-universal",
  files,
}, null, 2)}\n`);
NODE
  (cd "$update_payload" && zip -q -r "$update_artifact" .)
  node --input-type=module - "$unsigned_update_manifest" "$update_artifact" "$version" "$release_manifest" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [destination, artifactPath, version, releasePath] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
const data = fs.readFileSync(artifactPath);
fs.writeFileSync(destination, `${JSON.stringify({
  schemaVersion: 1,
  product: "AkuBrowser",
  channel: "stable",
  version,
  runtimeRevision: release.components.akuBridge.runtimeRevision,
  bridgeContractVersion: release.components.akuBridge.contractVersion,
  publishedAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  artifact: {
    url: `https://github.com/abangkis/AkuBrowser/releases/download/v${version}/${path.basename(artifactPath)}`,
    size: data.length,
    sha256: crypto.createHash("sha256").update(data).digest("hex"),
  },
}, null, 2)}\n`);
NODE
  derived_update_public_key="$(cd "$browser_root/installer/windows" && GOCACHE="$go_cache" GOMODCACHE="$go_mod_cache" go run -buildvcs=false ./cmd/sign-update-manifest -manifest "$unsigned_update_manifest" -private-key "$update_signing_private_key" -output "$update_manifest")"
  [[ "$derived_update_public_key" = "$update_public_key" ]] || die "runtime-update private key does not match the public key pinned into the native host"
  shasum -a 256 "$update_artifact" > "$update_artifact.sha256"
fi

pkgbuild --root "$payload_root" --scripts "$scripts_root" --identifier com.akubrowser.runtime --version "$version" --install-location / "$component_package"
product_args=(--distribution "$distribution_file" --package-path "$build_root" --resources "$resources_root")
[[ -z "$installer_identity" ]] || product_args+=(--sign "$installer_identity")
productbuild "${product_args[@]}" "$versioned_package"
cp "$versioned_package" "$stable_package"

if [[ -n "$notary_profile" ]]; then
  xcrun notarytool submit "$versioned_package" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$versioned_package"
  cp "$versioned_package" "$stable_package"
fi

shasum -a 256 "$versioned_package" > "$versioned_package.sha256"
shasum -a 256 "$stable_package" > "$stable_package.sha256"
pkgutil --check-signature "$versioned_package" || [[ "$unsigned_local" -eq 1 ]]
lipo -archs "$host_root/AkuBrowserRuntimeHost"
lipo -archs "$version_root/AkuSidecar"

echo "macOS runtime installer: $versioned_package"
echo "stable release asset: $stable_package"
