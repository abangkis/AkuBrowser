[CmdletBinding()]
param([switch] $SkipGoTests)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$cacheRoot = Join-Path $workspaceRoot ".go-cache"
$env:GOCACHE = Join-Path $cacheRoot "build"
$env:GOMODCACHE = Join-Path $cacheRoot "mod"
$env:GOTMPDIR = Join-Path $cacheRoot "tmp"
foreach ($directory in @($env:GOCACHE, $env:GOMODCACHE, $env:GOTMPDIR)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$release = Get-Content (Join-Path $browserRoot "release\release-manifest.json") -Raw | ConvertFrom-Json

$updaterSource = Get-Content (Join-Path $bridgeRoot "native-host\runtime_updater.go") -Raw
$manifestSource = Get-Content (Join-Path $bridgeRoot "native-host\update_manifest.go") -Raw
$platformSource = Get-Content (Join-Path $bridgeRoot "native-host\platform.go") -Raw
$sidecarServer = Get-Content (Join-Path $sidecarRoot "internal\httpapi\server.go") -Raw
$builder = Get-Content (Join-Path $browserRoot "scripts\build-windows-runtime-installer.ps1") -Raw
$macBuilder = Get-Content (Join-Path $browserRoot "scripts\build-macos-runtime-installer.sh") -Raw
$macStableGate = Get-Content (Join-Path $browserRoot "scripts\run-macos-stable-gate.sh") -Raw
$workflow = Get-Content (Join-Path $browserRoot ".github\workflows\windows-runtime-installer.yml") -Raw
$distributionContract = Get-Content (Join-Path $browserRoot "docs\chrome-store-distribution-contract.md") -Raw
$nativeProtocolV2 = Get-Content (Join-Path $browserRoot "contracts\native-runtime-messaging.schema.json") -Raw | ConvertFrom-Json
$nativeProtocolV1 = Get-Content (Join-Path $browserRoot "contracts\native-runtime-messaging-v1.schema.json") -Raw | ConvertFrom-Json
$sidecarManifestSchema = Get-Content (Join-Path $browserRoot "contracts\runtime-update-manifest.schema.json") -Raw | ConvertFrom-Json
$legacyManifestSchema = Get-Content (Join-Path $browserRoot "contracts\runtime-update-manifest-v1.schema.json") -Raw | ConvertFrom-Json

foreach ($required in @(
    "https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuSidecarUpdate.json",
    "https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuSidecarUpdate-",
    "https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeUpdate.json",
    "https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeUpdate-",
    "platformUpdateManifestURL"
)) {
    Assert-True ($platformSource.Contains($required)) "Update manifest URL boundary is missing: $required"
}
foreach ($required in @("ed25519.Verify", "pinnedUpdatePublicKey")) {
    Assert-True ($manifestSource.Contains($required)) "Signed manifest boundary is missing: $required"
}
foreach ($required in @(
    "extractVerifiedRuntimeArchive",
    '"-runtime-candidate-probe-schema", "2"',
    "waiting_for_idle",
    "persistActiveRuntime",
    "rolling_back",
    "cleanupVersions",
    "update-audit.jsonl"
)) {
    Assert-True ($updaterSource.Contains($required)) "Updater lifecycle boundary is missing: $required"
}
foreach ($required in @("/api/runtime/update-readiness", "/api/runtime/shutdown-if-idle", "X-Aku-Runtime-Control-Token")) {
    Assert-True ($sidecarServer.Contains($required)) "Runtime readiness handshake is missing: $required"
}
foreach ($required in @(
    "UpdatePublicKey",
    "UpdateSigningPrivateKeyPath",
    "AkuSidecarUpdate.json",
    "AkuSidecar-",
    "AkuBrowserRuntimeUpdate.json"
)) {
    Assert-True ($builder.Contains($required)) "Release builder does not enforce: $required"
}
Assert-True ($builder.Contains('-X main.runtimeHostVersion=$nativeHostVersion')) "Windows builder must inject the release-declared Native Host version."
Assert-True ($macBuilder.Contains('-X main.runtimeHostVersion=$native_host_version')) "macOS builder must inject the release-declared Native Host version."
Assert-True ($builder.Contains('check-native-host-min-version.mjs')) "Windows builder must gate packaged Native Host SemVer against Sidecar minHostVersion."
Assert-True ($macBuilder.Contains('check-native-host-min-version.mjs')) "macOS builder must gate packaged Native Host SemVer against Sidecar minHostVersion."
Assert-True ($builder.Contains('/DAPP_VERSION=$sidecarVersion')) "Windows installer identity must follow the independently versioned Sidecar."
Assert-True ($macBuilder.Contains('--version "$sidecar_version"')) "macOS installer identity must follow the independently versioned Sidecar."
Assert-True ($macBuilder.Contains('unsigned stable installers require --update-signing-private-key')) "Public stable macOS builds must not omit the signed Sidecar feed."
foreach ($required in @(
    '--release-version <version>',
    '--sidecar-version <version>',
    '--update-signing-private-key <path>',
    'AkuBrowserRuntimeSetup-${sidecar_version}-macos-universal.pkg',
    'AkuSidecar-${sidecar_version}-macos-universal.zip',
    'AkuSidecarUpdate-macos-universal.json',
    'releaseTag: `v${sidecarVersion}`'
)) {
    Assert-True ($macStableGate.Contains($required)) "macOS stable gate does not preserve the independent Sidecar release boundary: $required"
}
Assert-True (-not $macStableGate.Contains('AkuBrowserRuntimeSetup-${release_version}-macos-universal.pkg')) "macOS stable gate must not derive the installer name from the top-level AkuBrowser version."
Assert-True ([string]$release.distribution.chromeStore.nativeHost.version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') "Release manifest must declare a valid Native Host version."
Assert-True ($sidecarManifestSchema.properties.schemaVersion.const -eq 2 -and $sidecarManifestSchema.properties.product.const -eq "AkuSidecar") "Current update schema must describe AkuSidecar manifest v2."
foreach ($required in @("sidecarVersion", "runtimeRevision", "minHostVersion", "bridgeCompatibility", "databaseCompatibility", "artifact", "signature")) {
    Assert-True ($sidecarManifestSchema.required -contains $required) "AkuSidecar manifest v2 is missing required field: $required"
}
Assert-True ($legacyManifestSchema.properties.schemaVersion.const -eq 1 -and $legacyManifestSchema.properties.product.const -eq "AkuBrowser") "Legacy update schema must remain frozen at v1."
Assert-True ($sidecarManifestSchema.properties.databaseCompatibility.properties.rollbackSafe.const -eq $true) "AkuSidecar manifest v2 must require rollbackSafe=true."
Assert-True ($sidecarManifestSchema.allOf.Count -ge 1) "AkuSidecar manifest v2 must constrain deadline to mandatory urgency classes."
Assert-True ($builder.Contains('channel = if ($UnsignedLocalCandidate) { $release.channel } else { "stable" }')) "Production installer must activate the stable update channel without changing portable preview authority."
foreach ($required in @("RUNTIME_UPDATE_SIGNING_PRIVATE_KEY_BASE64", "RUNTIME_UPDATE_PUBLIC_KEY_BASE64")) {
    Assert-True ($workflow.Contains($required)) "Release workflow secret is missing: $required"
}
foreach ($required in @(
    'browser_ref:',
    'bridge_ref:',
    'sidecar_ref:',
    "-cnotmatch '^[0-9a-f]{40}`$'",
    'git -C "AkuWorkspace/$repository" rev-parse HEAD',
    'promote_latest:',
    'AkuBrowserRuntimeSetup-$sidecarVersion.exe',
    'AkuBrowserRuntimeSetup-$sidecarVersion.exe.sha256',
    'AkuSidecar-$sidecarVersion-windows-x64.zip.sha256',
    'AkuBrowserRuntimeSetup-$sidecarVersion-macos-universal.pkg.sha256',
    'AkuSidecar-$sidecarVersion-macos-universal.zip.sha256',
    '$versionedInstaller',
    'AkuBrowserRuntimeSetup-*.exe',
    'AkuSidecarUpdate-macos-universal.json',
    '$legacyTupleIsAligned',
    'A distinct previous Latest release is required to carry forward frozen v1 feeds',
    'run .\cmd\sign-update-manifest',
    '-verify-signed $feedPath',
    'Carried legacy feed changed bytes during upload',
    'Legacy feed references a missing immutable archive',
    'AkuBrowserRuntimeUpdate-macos-universal.json',
    'Cannot promote Latest before the cross-platform asset is attached',
    'gh release edit $env:RELEASE_TAG --draft=false --prerelease=false --latest'
)) {
    Assert-True ($workflow.Contains($required)) "Latest promotion is missing its cross-platform gate: $required"
}
Assert-True (-not $workflow.Contains('source_ref:')) "Stable workflow must not reuse one cross-repository ref."
$promotionStep = $workflow.IndexOf('- name: Promote fully assembled cross-platform release')
$latestCommand = $workflow.IndexOf('gh release edit $env:RELEASE_TAG --draft=false --prerelease=false --latest')
Assert-True ($promotionStep -ge 0 -and $latestCommand -gt $promotionStep) "Windows asset upload must not promote Latest outside the explicit cross-platform promotion step."
$workflowLines = $workflow -split '\r?\n'
$insideRunBlock = $false
foreach ($workflowLine in $workflowLines) {
    if ($workflowLine -match '^\s{8}run:\s*(?:\|.*)?$') {
        $insideRunBlock = $true
        continue
    }
    if ($insideRunBlock -and $workflowLine -match '^\s{6}- name:') {
        $insideRunBlock = $false
    }
    if ($insideRunBlock) {
        Assert-True (-not $workflowLine.Contains('${{ inputs.')) "Workflow dispatch inputs must enter PowerShell through env, never expression interpolation."
    }
}
foreach ($required in @(
    'Native protocol version: `2`',
    'one exact v1 migration fallback',
    'Bridge protocol major/minor',
    'bounded capability list',
    'explicit Sidecar bootstrap version packaged into the Store Bridge',
    'release.components.akuSidecar.version',
    'Setup never resolves native code through',
    'host_upgrade_required',
    'update.targetVersion',
    'byte-for-byte from previous Latest'
)) {
    Assert-True ($distributionContract.Contains($required)) "Chrome Store distribution contract retains a stale exact-tuple lifecycle boundary: $required"
}
Assert-True (-not $distributionContract.Contains('outside protocol v1')) "Chrome Store distribution contract must describe the v2 lifecycle boundary."
Assert-True ($nativeProtocolV2.'$defs'.protocolVersion.const -eq 2) "Current Native Messaging schema must be protocol v2."
Assert-True ($nativeProtocolV2.'$defs'.action.enum -contains "reconcile_runtime") "Protocol v2 must include quiet runtime reconciliation."
Assert-True ($nativeProtocolV1.'$defs'.protocolVersion.const -eq 1) "Legacy Native Messaging schema must remain protocol v1."
Assert-True ($nativeProtocolV1.'$defs'.action.enum -notcontains "reconcile_runtime") "Protocol v1 must not gain the v2 reconcile action."
node (Join-Path $browserRoot "scripts\validate-native-runtime-contracts.mjs")
if ($LASTEXITCODE -ne 0) { throw "Native Messaging contract examples failed validation." }

if (-not $SkipGoTests) {
    Push-Location (Join-Path $bridgeRoot "native-host")
    try {
        go test -count=1 ./...
        if ($LASTEXITCODE -ne 0) { throw "Native host updater tests failed." }
    }
    finally { Pop-Location }

    Push-Location $sidecarRoot
    try {
        go test -count=1 ./...
        if ($LASTEXITCODE -ne 0) { throw "AkuSidecar readiness tests failed." }
    }
    finally { Pop-Location }

    Push-Location (Join-Path $browserRoot "installer\windows")
    try {
        go test -count=1 ./...
        if ($LASTEXITCODE -ne 0) { throw "Runtime release signing tests failed." }
    }
    finally { Pop-Location }
}

[ordered]@{
    status = "ok"
    stage = 7
    version = $release.components.akuSidecar.version
    channel = "stable"
    signedManifestBoundary = $true
    installerTrustState = $release.distribution.chromeStore.nativeRuntimeInstallers.'windows-x64'.trustState
    fixedOrigin = $true
    readinessHandshake = $true
    atomicActivation = $true
    oneVersionRollback = $true
    boundedAudit = $true
} | ConvertTo-Json
