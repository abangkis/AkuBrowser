#!/usr/bin/env bash
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_manifest="$browser_root/release/release-manifest.json"
version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).version)' "$release_manifest")"
extension_id="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).distribution.chromeStore.extensionId)' "$release_manifest")"
package_path="${1:-$browser_root/artifacts/AkuBrowserRuntimeSetup-${version}-macos-universal-unsigned-local.pkg}"
[[ -f "$package_path" ]] || die "installer package is missing: $package_path"

inspect_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-pkg-test.XXXXXX")"
trap 'rm -rf -- "$inspect_root"' EXIT
pkgutil --expand-full "$package_path" "$inspect_root/expanded"

distribution="$inspect_root/expanded/Distribution"
component="$inspect_root/expanded/AkuBrowserRuntime.pkg"
payload="$component/Payload/Library/Application Support/AkuBrowser"
postinstall="$component/Scripts/postinstall"
host="$payload/host/AkuBrowserRuntimeHost"
sidecar="$payload/runtime/versions/$version/AkuSidecar"
c2pa_tool="$payload/runtime/versions/$version/c2patool"
current="$payload/runtime/current.json"

for required in "$distribution" "$postinstall" "$host" "$sidecar" "$current" "$payload/Uninstall-AkuBrowserRuntime.command"; do
  [[ -f "$required" ]] || die "package payload is missing: $required"
done
grep -q 'enable_currentUserHome="true"' "$distribution" || die "package is not current-user scoped"
grep -q 'enable_localSystem="false"' "$distribution" || die "package unexpectedly permits system installation"
grep -q "runtime/versions/$version/AkuSidecar" "$postinstall" || die "postinstall version drifted"
grep -q "chrome-extension://$extension_id/" "$postinstall" || die "production extension origin is missing"
grep -q 'Google/Chrome/NativeMessagingHosts' "$postinstall" || die "Chrome Native Messaging registration is missing"

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

node --input-type=module - "$current" "$version" <<'NODE'
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

pkgutil --check-signature "$package_path" >/dev/null || [[ "$package_path" == *-unsigned-local.pkg ]]

update_artifact="$browser_root/artifacts/AkuBrowserRuntime-${version}-macos-universal.zip"
update_manifest="$browser_root/artifacts/AkuBrowserRuntimeUpdate-macos-universal.json"
if [[ -f "$update_artifact" || -f "$update_manifest" ]]; then
  [[ -f "$update_artifact" && -f "$update_manifest" ]] || die "macOS update artifact and manifest must be produced together"
  node --input-type=module - "$update_artifact" "$update_manifest" "$version" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [artifactPath, manifestPath, version] = process.argv.slice(2);
const artifact = fs.readFileSync(artifactPath);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const expectedName = `AkuBrowserRuntime-${version}-macos-universal.zip`;
if (manifest.schemaVersion !== 1 || manifest.product !== "AkuBrowser" || manifest.channel !== "stable") throw new Error("update manifest identity is invalid");
if (manifest.version !== version || !manifest.artifact.url.endsWith(`/v${version}/${expectedName}`)) throw new Error("update artifact URL is invalid");
if (manifest.artifact.size !== artifact.length || manifest.artifact.sha256 !== crypto.createHash("sha256").update(artifact).digest("hex")) throw new Error("update artifact digest is invalid");
if (manifest.signature?.algorithm !== "ed25519" || manifest.signature?.keyId !== "aku-runtime-stable-v1" || manifest.signature?.value?.length !== 88) throw new Error("update signature metadata is invalid");
NODE
  mkdir -p "$inspect_root/update"
  ditto -x -k "$update_artifact" "$inspect_root/update"
  lipo -archs "$inspect_root/update/AkuSidecar" | grep -q x86_64 || die "update Sidecar lacks x86_64"
  lipo -archs "$inspect_root/update/AkuSidecar" | grep -q arm64 || die "update Sidecar lacks arm64"
  node --input-type=module - "$inspect_root/update" "$version" <<'NODE'
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
fi
echo "macOS runtime installer structural test passed: $package_path"
