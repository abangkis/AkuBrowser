#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/build-macos-3b-acceptance-kit.sh [options]

Required:
  --final-kit <directory>       Finalized Mac release kit verified after Windows signing

Optional:
  --output-root <directory>     Fresh Step 3B kit directory
  --c2pa-tool <path>            Universal c2patool binary
  --allow-dirty                 Allow dirty sources for tooling development only
  --skip-validation             Skip source test suites inside the installer builder
  -h, --help                    Show this help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"; }

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$browser_root/.." && pwd)"
bridge_root="$workspace_root/AkuBridge"
sidecar_root="$workspace_root/AkuSidecar"
release_manifest="$browser_root/release/release-manifest.json"
identity_registry="$browser_root/config/bridge-identities.json"
final_kit=""
output_root=""
c2pa_tool="$sidecar_root/runtime/dev/macos-universal/c2patool"
allow_dirty=0
skip_validation=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --final-kit) final_kit="$2"; shift 2 ;;
    --output-root) output_root="$2"; shift 2 ;;
    --c2pa-tool) c2pa_tool="$2"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --skip-validation) skip_validation=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$(uname -s)" = "Darwin" ]] || die "run the macOS Step 3B kit builder on macOS"
[[ -n "$final_kit" ]] || die "--final-kit is required"
for command_name in git go lipo node pkgutil shasum zip; do require_command "$command_name"; done

final_kit="$(cd "$final_kit" && pwd)"
final_kit_manifest="$final_kit/release-kit.json"
[[ -f "$final_kit_manifest" ]] || die "final release-kit.json is missing: $final_kit_manifest"
[[ -f "$c2pa_tool" ]] || die "universal c2patool is missing: $c2pa_tool"

release_version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).version)' "$release_manifest")"
sidecar_version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).components.akuSidecar.version)' "$release_manifest")"
bridge_version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).components.akuBridge.version)' "$release_manifest")"
development_id="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).profiles.development.extensionId)' "$identity_registry")"
production_id="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).profiles.production.extensionId)' "$identity_registry")"

final_receipt="$(node --input-type=module - "$final_kit_manifest" "$final_kit" "$release_version" "$sidecar_version" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [manifestPath, kitRoot, releaseVersion, sidecarVersion] = process.argv.slice(2);
const kit = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (kit.status !== "ok" || kit.releaseVersion !== releaseVersion || kit.sidecarVersion !== sidecarVersion) throw new Error("final Mac kit does not match the active release");
if (kit.signing?.updateManifests !== "ed25519" || kit.signing?.privateKeyLocation !== "windows-only") throw new Error("final Mac kit was not completed through the Windows signing handoff");
for (const asset of kit.publishAssets ?? []) {
  const file = path.join(kitRoot, ...asset.path.split("/"));
  if (!fs.existsSync(file)) throw new Error(`final Mac asset is missing: ${asset.path}`);
  const data = fs.readFileSync(file);
  if (data.length !== asset.bytes || crypto.createHash("sha256").update(data).digest("hex") !== asset.sha256) throw new Error(`final Mac asset drifted: ${asset.path}`);
}
const receiptName = `AkuBrowser-${releaseVersion}-macos-signing-receipt.json`;
for (const name of ["AkuSidecarUpdate-macos-universal.json", receiptName]) {
  if (!(kit.publishAssets ?? []).some((asset) => asset.path === `publish/${name}`)) throw new Error(`final Mac kit is missing ${name}`);
}
process.stdout.write(path.join(kitRoot, "publish", receiptName));
NODE
)"

update_public_key="$(node --input-type=module -e '
  import fs from "node:fs";
  const receipt = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (receipt.status !== "signed" || receipt.publicKey?.algorithm !== "Ed25519" || receipt.publicKey?.keyId !== "aku-runtime-stable-v1") throw new Error("Mac signing receipt is invalid");
  if (!Array.isArray(receipt.signedManifests) || !receipt.signedManifests.some(({ outputName }) => outputName === "AkuSidecarUpdate-macos-universal.json")) throw new Error("Mac signing receipt has no signed Sidecar manifest");
  console.log(receipt.publicKey.base64);
' "$final_receipt")"

go_cache="${TMPDIR:-/tmp}/akubrowser-go-cache"
go_mod_cache="${TMPDIR:-/tmp}/akubrowser-go-mod-cache"
mkdir -p "$go_cache" "$go_mod_cache"
for signed_manifest in \
  "$final_kit/publish/AkuSidecarUpdate-macos-universal.json" \
  "$final_kit/publish/AkuBrowserRuntimeUpdate-macos-universal.json"; do
  [[ ! -f "$signed_manifest" ]] || (
    cd "$browser_root/installer/windows"
    GOCACHE="$go_cache" GOMODCACHE="$go_mod_cache" \
      go run -buildvcs=false ./cmd/sign-update-manifest \
        -verify-signed "$signed_manifest" \
        -public-key "$update_public_key"
  )
done

node "$browser_root/scripts/bridge-extension-identity.mjs" "$identity_registry" "$bridge_root/manifest.json" development >/dev/null
for repository in "$bridge_root" "$sidecar_root"; do
  [[ -z "$(git -C "$repository" status --porcelain)" ]] || die "release source is dirty: $repository"
done
if [[ "$allow_dirty" -eq 0 ]]; then
  [[ -z "$(git -C "$browser_root" status --porcelain)" ]] || die "release tooling source is dirty; commit it or use --allow-dirty only while developing the generator"
fi

current_browser_sha="$(git -C "$browser_root" rev-parse HEAD)"
final_tooling_sha="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).toolingCommits?.akuBrowser ?? "")' "$final_kit_manifest")"
tooling_drift_json="$(node "$browser_root/scripts/verify-release-tooling-drift.mjs" "$browser_root" "$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).sourceCommits?.akuBrowser ?? "")' "$final_kit_manifest")" "$current_browser_sha")"
node --input-type=module - "$final_kit_manifest" "$browser_root" "$bridge_root" "$sidecar_root" "$final_tooling_sha" "$current_browser_sha" <<'NODE'
import fs from "node:fs";
import { execFileSync } from "node:child_process";
const [kitPath, browserRoot, bridgeRoot, sidecarRoot, finalToolingSha, currentBrowserSha] = process.argv.slice(2);
const kit = JSON.parse(fs.readFileSync(kitPath, "utf8"));
const head = (root) => execFileSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
if (head(bridgeRoot) !== kit.sourceCommits?.akuBridge || head(sidecarRoot) !== kit.sourceCommits?.akuSidecar) throw new Error("Bridge or Sidecar HEAD differs from the finalized Mac source tuple");
if (head(browserRoot) !== currentBrowserSha) throw new Error("AkuBrowser HEAD changed during acceptance-kit generation");
try {
  execFileSync("git", ["-C", browserRoot, "merge-base", "--is-ancestor", finalToolingSha, currentBrowserSha], { stdio: "ignore" });
} catch {
  throw new Error("AkuBrowser HEAD is not a descendant of the finalized Mac tooling commit");
}
NODE

if [[ -z "$output_root" ]]; then
  output_root="$browser_root/artifacts/stable-${sidecar_version}-macos-3b"
fi
output_root="$(node --input-type=module -e 'import path from "node:path"; console.log(path.resolve(process.argv[1]))' "$output_root")"
case "$output_root" in
  "$browser_root"/*) ;;
  *) die "--output-root must stay inside $browser_root" ;;
esac
mkdir -p "$(dirname "$output_root")"
if [[ -e "$output_root" ]]; then
  [[ -d "$output_root" && -z "$(find "$output_root" -mindepth 1 -print -quit)" ]] || die "output directory must be new or empty: $output_root"
  rmdir "$output_root"
fi
building_root="$output_root.building"
[[ ! -e "$building_root" ]] || die "prior incomplete Step 3B staging exists: $building_root"
acceptance_root="$building_root/acceptance"
unpacked_name="AkuBridge-${bridge_version}-prestore-unpacked"
unpacked_root="$acceptance_root/$unpacked_name"
installer_name="AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal-unsigned-local.pkg"
mkdir -p "$unpacked_root"
cleanup() { [[ ! -d "$building_root" ]] || rm -rf -- "$building_root"; }
trap cleanup EXIT

verification_json="$(node "$bridge_root/scripts/verify-extension-package.mjs")"
node --input-type=module - "$bridge_root" "$unpacked_root" "$verification_json" <<'NODE'
import fs from "node:fs";
import path from "node:path";
const [sourceRoot, destinationRoot, verificationJson] = process.argv.slice(2);
const verification = JSON.parse(verificationJson);
for (const entry of verification.files) {
  const source = path.join(sourceRoot, ...entry.path.split("/"));
  const destination = path.join(destinationRoot, ...entry.path.split("/"));
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}
NODE

package_fingerprint_json="$(node "$browser_root/scripts/fingerprint-extension-directory.mjs" "$unpacked_root")"
bridge_zip="$acceptance_root/$unpacked_name.zip"
(cd "$unpacked_root" && zip -q -r "$bridge_zip" .)
(cd "$acceptance_root" && shasum -a 256 "$unpacked_name.zip" > "$unpacked_name.zip.sha256")

node --input-type=module - "$acceptance_root/$unpacked_name.receipt.json" "$bridge_zip" "$verification_json" "$package_fingerprint_json" "$bridge_root" "$development_id" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
const [destination, zipPath, verificationJson, fingerprintJson, bridgeRoot, developmentId] = process.argv.slice(2);
const verification = JSON.parse(verificationJson);
const fingerprint = JSON.parse(fingerprintJson);
const data = fs.readFileSync(zipPath);
const receipt = {
  schemaVersion: 1,
  package: path.basename(zipPath),
  version: verification.version,
  chromeVersion: verification.chromeVersion,
  sha256: crypto.createHash("sha256").update(data).digest("hex"),
  extensionFingerprint: fingerprint.fingerprint,
  fileCount: fingerprint.files.length,
  identity: { profile: "development", distribution: "unpacked", extensionId: developmentId },
  source: { repository: "AkuBridge", commit: execFileSync("git", ["-C", bridgeRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(), dirty: false },
};
fs.writeFileSync(destination, `${JSON.stringify(receipt, null, 2)}\n`);
NODE

installer_stage="$building_root/installer-stage"
installer_args=(
  --output-root "$installer_stage"
  --bridge-identity-profile development
  --c2pa-tool "$c2pa_tool"
  --update-public-key "$update_public_key"
  --unsigned-local-candidate
)
[[ "$allow_dirty" -eq 0 ]] || installer_args+=(--allow-dirty)
[[ "$skip_validation" -eq 0 ]] || installer_args+=(--skip-validation)
"$browser_root/scripts/build-macos-runtime-installer.sh" "${installer_args[@]}"
cp "$installer_stage/$installer_name" "$acceptance_root/$installer_name"
cp "$installer_stage/$installer_name.sha256" "$acceptance_root/$installer_name.sha256"
"$browser_root/scripts/test-macos-runtime-installer.sh" \
  --bridge-identity-profile development \
  "$acceptance_root/$installer_name"

cp "$browser_root/docs/macos-clean-machine-3b.md" "$acceptance_root/STEP-3B-CHECKLIST.md"

node --input-type=module - "$acceptance_root/README.md" "$release_version" "$unpacked_name" "$installer_name" "$development_id" "$production_id" <<'NODE'
import fs from "node:fs";
const [destination, releaseVersion, unpackedName, installerName, developmentId, productionId] = process.argv.slice(2);
fs.writeFileSync(destination, `# macOS Step 3B acceptance kit ${releaseVersion}\n\nThis entire folder is local test input/evidence only. Never upload it to GitHub or the Chrome Web Store.\n\n1. In Chrome, disable any production AkuBrowser extension and Load unpacked from \`${unpackedName}/\`.\n2. Verify extension ID \`${developmentId}\`.\n3. Run \`${installerName}\`; it is universal, unsigned, and bound to that development ID.\n4. Return to Setup and run Check runtime, Check Codex, source consent/login, and one full Update now.\n5. Complete every item in \`STEP-3B-CHECKLIST.md\`.\n\nThe production ID is \`${productionId}\` and must not be enabled during this pre-Store test. The finalized Windows-signed manifest hashes are recorded in \`../acceptance-kit.json\`; signed production files remain in the separate finalized release kit.\n`);
NODE

node --input-type=module - "$building_root/acceptance-kit.json" "$acceptance_root" "$final_kit_manifest" "$final_receipt" "$package_fingerprint_json" "$release_version" "$sidecar_version" "$bridge_version" "$development_id" "$allow_dirty" "$current_browser_sha" "$tooling_drift_json" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [destination, acceptanceRoot, finalKitPath, receiptPath, fingerprintJson, releaseVersion, sidecarVersion, bridgeVersion, developmentId, allowDirty, currentBrowserSha, toolingDriftJson] = process.argv.slice(2);
const hash = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const finalKit = JSON.parse(fs.readFileSync(finalKitPath, "utf8"));
const receipt = JSON.parse(fs.readFileSync(receiptPath, "utf8"));
const files = fs.readdirSync(acceptanceRoot).filter((name) => fs.statSync(path.join(acceptanceRoot, name)).isFile()).sort().map((name) => {
  const file = path.join(acceptanceRoot, name);
  return { path: `acceptance/${name}`, bytes: fs.statSync(file).size, sha256: hash(file) };
});
const kit = {
  schemaVersion: 1,
  status: "ok",
  purpose: "macos-clean-machine-step-3b",
  publishable: false,
  releaseVersion,
  sidecarVersion,
  sourceCommits: finalKit.sourceCommits,
  toolingCommits: finalKit.toolingCommits,
  acceptanceToolingCommit: currentBrowserSha,
  toolingDrift: JSON.parse(toolingDriftJson),
  sourceDirtyAllowed: allowDirty === "1",
  identity: { profile: "development", extensionId: developmentId },
  unpackedBridge: { path: `acceptance/AkuBridge-${bridgeVersion}-prestore-unpacked`, fingerprint: JSON.parse(fingerprintJson).fingerprint },
  finalizedSigningEvidence: {
    receipt: path.basename(receiptPath),
    receiptSha256: hash(receiptPath),
    signedManifests: receipt.signedManifests.map(({ outputName, signedSha256 }) => ({ outputName, signedSha256 })),
  },
  acceptanceAssets: files,
};
fs.writeFileSync(destination, `${JSON.stringify(kit, null, 2)}\n`);
NODE

node --input-type=module - "$building_root/acceptance-kit.json" "$acceptance_root" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
const [manifestPath, acceptanceRoot] = process.argv.slice(2);
const kit = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const expected = new Map(kit.acceptanceAssets.map((asset) => [asset.path.replace(/^acceptance\//, ""), asset]));
for (const name of fs.readdirSync(acceptanceRoot)) {
  const file = path.join(acceptanceRoot, name);
  if (!fs.statSync(file).isFile()) continue;
  const asset = expected.get(name);
  if (!asset) throw new Error(`unexpected acceptance file: ${name}`);
  const data = fs.readFileSync(file);
  if (data.length !== asset.bytes || crypto.createHash("sha256").update(data).digest("hex") !== asset.sha256) throw new Error(`acceptance file drifted: ${name}`);
}
NODE

rm -rf -- "$installer_stage"
mv "$building_root" "$output_root"
trap - EXIT
echo "macOS Step 3B acceptance kit: $output_root"
echo "Load unpacked: $output_root/acceptance/$unpacked_name"
echo "Installer: $output_root/acceptance/$installer_name"
