#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/build-macos-preview.sh [options]

Options:
  --architecture <x64|arm64|universal>  Build target (default: host architecture)
  --output-root <path>                  Artifact directory (default: artifacts)
  --skip-validation                     Skip source tests and package checks
  --allow-dirty                         Build from non-clean source trees
  -h, --help                            Show this help
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$browser_root/.." && pwd)"
bridge_root="$workspace_root/AkuBridge"
sidecar_root="$workspace_root/AkuSidecar"
release_manifest_path="$browser_root/release/release-manifest.json"
bridge_identity_registry_path="$browser_root/config/bridge-identities.json"

case "$(uname -m)" in
  x86_64) default_architecture="x64" ;;
  arm64|aarch64) default_architecture="arm64" ;;
  *) die "unsupported macOS host architecture: $(uname -m)" ;;
esac

architecture="$default_architecture"
output_root="$browser_root/artifacts"
skip_validation=0
allow_dirty=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --architecture)
      [[ $# -ge 2 ]] || die "--architecture requires a value"
      architecture="$2"
      shift 2
      ;;
    --output-root)
      [[ $# -ge 2 ]] || die "--output-root requires a value"
      output_root="$2"
      shift 2
      ;;
    --skip-validation)
      skip_validation=1
      shift
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
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

case "$architecture" in
  x64|arm64|universal) ;;
  *) die "architecture must be x64, arm64, or universal" ;;
esac

for command_name in git go node npm shasum zip; do
  require_command "$command_name"
done

[[ -f "$release_manifest_path" ]] || die "release manifest is missing: $release_manifest_path"
[[ -f "$bridge_identity_registry_path" ]] || die "Bridge identity registry is missing: $bridge_identity_registry_path"
[[ -d "$bridge_root" ]] || die "AkuBridge checkout is missing: $bridge_root"
[[ -d "$sidecar_root" ]] || die "AkuSidecar checkout is missing: $sidecar_root"

if [[ "$skip_validation" -eq 0 ]]; then
  (
    cd "$sidecar_root"
    go test -p 1 ./...
  )
  (
    cd "$bridge_root"
    npm run check
  )
fi

node --input-type=module - "$browser_root" "$bridge_root" "$sidecar_root" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [browserRoot, bridgeRoot, sidecarRoot] = process.argv.slice(2);
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const release = readJson(path.join(browserRoot, "release/release-manifest.json"));
const bridgeIdentityRegistry = readJson(path.join(browserRoot, "config/bridge-identities.json"));
const bridgePackage = readJson(path.join(bridgeRoot, "package.json"));
const bridgeManifest = readJson(path.join(bridgeRoot, "manifest.json"));
const sidecarConfig = readJson(path.join(sidecarRoot, "config/sidecar.json"));
const domain = fs.readFileSync(path.join(sidecarRoot, "internal/domain/types.go"), "utf8");

const fail = (message) => { throw new Error(message); };
if (release.distribution?.authorityRepository !== "AkuBrowser") fail("AkuBrowser is not the distribution authority");
if (bridgeIdentityRegistry.schemaVersion !== 1) fail("unsupported Bridge identity registry schema");
const bridgeIdentityProfile = release.distribution?.chromeStore?.bridgeIdentityProfile;
const bridgeIdentity = bridgeIdentityRegistry.profiles?.[bridgeIdentityProfile];
if (!bridgeIdentityProfile || !bridgeIdentity) fail("the release manifest must select an existing Bridge identity profile");
if (bridgeIdentity.distribution !== "chrome-web-store") fail("the macOS release must use a Chrome Web Store Bridge identity");
if (!/^[a-p]{32}$/.test(bridgeIdentity.extensionId ?? "")) {
  fail("the production Bridge identity must declare an exact Chrome Web Store extension ID");
}
if (Object.hasOwn(release.distribution?.chromeStore ?? {}, "extensionId")) {
  fail("the release manifest must not duplicate the Bridge extension ID");
}
if (Object.hasOwn(release.distribution?.chromeStore ?? {}, "extensionOrigin")) {
  fail("the release manifest must not duplicate the Bridge extension origin");
}
const macos = release.distribution?.macos;
if (macos?.format !== "portable-zip") fail("macOS distribution format must be portable-zip");
if (macos?.launcher !== "Start-AkuBrowser.command") fail("macOS launcher is not declared");
if (!macos?.architectures?.includes("x64") || !macos?.architectures?.includes("arm64")) {
  fail("macOS release architectures are not declared");
}
const localOrigins = release.distribution?.localOrigins ?? [];
for (const origin of ["http://127.0.0.1:11122", "http://localhost:11122"]) {
  if (!localOrigins.includes(origin)) fail(`local origin is not declared: ${origin}`);
}
if (bridgePackage.version !== bridgeManifest.version_name) fail("AkuBridge package and manifest versions differ");
if (bridgePackage.version !== release.components?.akuBridge?.version) fail("AkuBridge version drifted from the release tuple");
if (bridgeManifest.version !== release.components?.akuBridge?.chromeVersion) fail("AkuBridge Chrome version drifted from the release tuple");
if (sidecarConfig.reasoning?.provider !== "codex-app-server") fail("AkuSidecar must default to Codex App Server");
const sidecarVersion = release.components?.akuSidecar?.version;
const declaredSidecarVersion = domain.match(/ApplicationVersion\s*=\s*"([^"]+)"/)?.[1];
if (declaredSidecarVersion !== sidecarVersion) {
  fail("AkuSidecar version drifted from the release tuple");
}

const schemas = [
  "acquisition-plan.schema.json",
  "reasoning-result.schema.json",
  "semantic-event-resolution.schema.json",
  "ai-deep-detection.schema.json",
  "calibration-session.schema.json",
  "calibration-label.schema.json",
  "calibration-profile-snapshot.schema.json",
];
for (const schema of schemas) {
  const canonical = fs.readFileSync(path.join(browserRoot, "contracts", schema));
  const runtime = fs.readFileSync(path.join(sidecarRoot, "schemas", schema));
  if (!crypto.timingSafeEqual(crypto.createHash("sha256").update(canonical).digest(), crypto.createHash("sha256").update(runtime).digest())) {
    fail(`${schema} drifted between AkuBrowser and AkuSidecar`);
  }
}
NODE

mkdir -p "$output_root"
output_root="$(cd "$output_root" && pwd)"
version="$(node --input-type=module -e 'import fs from "node:fs"; console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).version)' "$release_manifest_path")"
artifact_name="AkuBrowser-${version}-macos-${architecture}"
artifact_root="$output_root/$artifact_name"
zip_path="$output_root/$artifact_name.zip"
zip_checksum_path="$zip_path.sha256"

if [[ "$artifact_root" != "$output_root"/* ]]; then die "artifact path escaped output root"; fi
rm -rf -- "$artifact_root" "$zip_path" "$zip_checksum_path"
mkdir -p "$artifact_root/AkuBridge" "$artifact_root/config" "$artifact_root/schemas"

dirty_repositories=()
for repository in "$browser_root" "$sidecar_root" "$bridge_root"; do
  status="$(git -C "$repository" status --porcelain)"
  if [[ -n "$status" ]]; then
    dirty_repositories+=("$repository")
  fi
done
if [[ "${#dirty_repositories[@]}" -gt 0 && "$allow_dirty" -eq 0 ]]; then
  die "release sources must be clean; use --allow-dirty for a local candidate"
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/akubrowser-macos-build.XXXXXX")"
cleanup() {
  rm -rf -- "$tmp_root"
}
trap cleanup EXIT

build_sidecar() {
  local goarch="$1"
  local output="$2"
  (
    cd "$sidecar_root"
    GOOS=darwin GOARCH="$goarch" CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$output" ./cmd/akusidecar
  )
}

case "$architecture" in
  x64)
    build_sidecar amd64 "$artifact_root/AkuSidecar"
    ;;
  arm64)
    build_sidecar arm64 "$artifact_root/AkuSidecar"
    ;;
  universal)
    require_command lipo
    build_sidecar amd64 "$tmp_root/AkuSidecar-x64"
    build_sidecar arm64 "$tmp_root/AkuSidecar-arm64"
    lipo -create "$tmp_root/AkuSidecar-x64" "$tmp_root/AkuSidecar-arm64" -output "$artifact_root/AkuSidecar"
    ;;
esac
chmod 755 "$artifact_root/AkuSidecar"

node --input-type=module - "$sidecar_root/config/sidecar.json" "$artifact_root/config/sidecar.json" "$release_manifest_path" "$bridge_identity_registry_path" <<'NODE'
import fs from "node:fs";
const [source, destination, releasePath, registryPath] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(source, "utf8"));
const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const profile = release.distribution?.chromeStore?.bridgeIdentityProfile;
const identity = registry.profiles?.[profile];
if (!identity || identity.distribution !== "chrome-web-store" || !/^[a-p]{32}$/.test(identity.extensionId ?? "")) {
  throw new Error("the release-selected Bridge identity is not a valid Chrome Web Store identity");
}
config.database.path = "data/aku-sidecar.db";
config.reasoning.executable = "";
config.bridge ??= {};
config.bridge.trustedExtensionOrigins = [`chrome-extension://${identity.extensionId}/`];
fs.writeFileSync(destination, `${JSON.stringify(config, null, 2)}\n`);
NODE

cp "$sidecar_root"/schemas/*.schema.json "$artifact_root/schemas/"

verification_path="$tmp_root/bridge-verification.json"
node "$bridge_root/scripts/verify-extension-package.mjs" > "$verification_path"
node --input-type=module - "$bridge_root" "$artifact_root/AkuBridge" "$verification_path" <<'NODE'
import fs from "node:fs";
import path from "node:path";
const [sourceRoot, destinationRoot, verificationPath] = process.argv.slice(2);
const verification = JSON.parse(fs.readFileSync(verificationPath, "utf8"));
for (const file of verification.files) {
  const source = path.join(sourceRoot, file.path);
  const destination = path.join(destinationRoot, file.path);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}
NODE

cp "$release_manifest_path" "$artifact_root/release-manifest.json"
cp "$browser_root/release/macos/Start-AkuBrowser.sh" "$artifact_root/Start-AkuBrowser.sh"
cp "$browser_root/release/macos/Start-AkuBrowser.command" "$artifact_root/Start-AkuBrowser.command"
cp "$browser_root/release/macos/README.md" "$artifact_root/README.md"
chmod 755 "$artifact_root/Start-AkuBrowser.sh" "$artifact_root/Start-AkuBrowser.command"

node --input-type=module - "$artifact_root/artifact-manifest.json" "$release_manifest_path" "$browser_root" "$sidecar_root" "$bridge_root" "$architecture" "$verification_path" <<'NODE'
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const [destination, releasePath, browserRoot, sidecarRoot, bridgeRoot, architecture, verificationPath] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
const bridgeIdentityRegistry = JSON.parse(fs.readFileSync(path.join(browserRoot, "config/bridge-identities.json"), "utf8"));
const bridgeIdentityProfile = release.distribution?.chromeStore?.bridgeIdentityProfile;
const bridgeIdentity = bridgeIdentityRegistry.profiles?.[bridgeIdentityProfile];
if (!bridgeIdentity) throw new Error("release-selected Bridge identity is missing from the registry");
const bridgeExtensionOrigin = `chrome-extension://${bridgeIdentity.extensionId}/`;
const verification = JSON.parse(fs.readFileSync(verificationPath, "utf8"));
const repositories = { akuBrowser: browserRoot, akuSidecar: sidecarRoot, akuBridge: bridgeRoot };
const sourceCommits = {};
const sourceDirty = [];
for (const [name, root] of Object.entries(repositories)) {
  sourceCommits[name] = execFileSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  if (execFileSync("git", ["-C", root, "status", "--porcelain"], { encoding: "utf8" }).trim()) sourceDirty.push(name);
}
const manifest = {
  schemaVersion: 1,
  product: release.product,
  version: release.version,
  channel: release.channel,
  target: `macos-${architecture}`,
  format: "portable-zip",
  builtAtUtc: new Date().toISOString(),
  sourceCommits,
  sourceDirty,
  components: release.components,
  akuBridgeFingerprint: verification.fingerprint,
  bridgeIdentity: {
    profile: bridgeIdentityProfile,
    distribution: bridgeIdentity.distribution,
    authority: "config/bridge-identities.json",
    extensionOrigin: bridgeExtensionOrigin,
  },
};
fs.writeFileSync(destination, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

(
  cd "$artifact_root"
  : > checksums.sha256
  while IFS= read -r file; do
    hash="$(shasum -a 256 "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$hash" "${file#./}" >> checksums.sha256
  done < <(find . -type f ! -name checksums.sha256 -print | LC_ALL=C sort)
)

(
  cd "$artifact_root"
  zip -qr "$zip_path" .
)
zip_hash="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
printf '%s  %s\n' "$zip_hash" "$(basename "$zip_path")" > "$zip_checksum_path"

node --input-type=module - "$artifact_root/artifact-manifest.json" "$artifact_root" "$zip_path" "$zip_hash" <<'NODE'
import fs from "node:fs";
const [manifestPath, artifactRoot, zipPath, zipHash] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const sidecarBytes = fs.statSync(`${artifactRoot}/AkuSidecar`).size;
const bridgeFiles = fs.readFileSync(`${artifactRoot}/release-manifest.json`, "utf8").length > 0
  ? fs.readdirSync(`${artifactRoot}/AkuBridge`, { recursive: true }).filter((file) => !file.endsWith("/")).length
  : 0;
console.log(JSON.stringify({
  status: "ok",
  version: manifest.version,
  target: manifest.target,
  artifactDirectory: artifactRoot,
  zip: zipPath,
  zipSha256: zipHash,
  sidecarBytes,
  bridgeFiles,
  sourceCommits: manifest.sourceCommits,
  sourceDirty: manifest.sourceDirty,
  bridgeIdentityProfile: manifest.bridgeIdentity.profile,
  bridgeExtensionOrigin: manifest.bridgeIdentity.extensionOrigin,
}, null, 2));
NODE
