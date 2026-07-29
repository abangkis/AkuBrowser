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
$sidecarServer = Get-Content (Join-Path $sidecarRoot "internal\httpapi\server.go") -Raw
$builder = Get-Content (Join-Path $browserRoot "scripts\build-windows-runtime-installer.ps1") -Raw
$workflow = Get-Content (Join-Path $browserRoot ".github\workflows\windows-runtime-installer.yml") -Raw

foreach ($required in @(
    "https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeUpdate.json",
    "ed25519.Verify",
    "pinnedUpdatePublicKey"
)) {
    Assert-True ($manifestSource.Contains($required)) "Signed manifest boundary is missing: $required"
}
foreach ($required in @(
    "extractVerifiedRuntimeArchive",
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
foreach ($required in @("UpdatePublicKey", "UpdateSigningPrivateKeyPath", "AkuBrowserRuntimeUpdate.json")) {
    Assert-True ($builder.Contains($required)) "Release builder does not enforce: $required"
}
Assert-True ($builder.Contains('channel = if ($UnsignedLocalCandidate) { $release.channel } else { "stable" }')) "Production installer must activate the stable update channel without changing portable preview authority."
foreach ($required in @("RUNTIME_UPDATE_SIGNING_PRIVATE_KEY_BASE64", "RUNTIME_UPDATE_PUBLIC_KEY_BASE64")) {
    Assert-True ($workflow.Contains($required)) "Release workflow secret is missing: $required"
}

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
    version = $release.version
    channel = "stable"
    signedManifest = $true
    fixedOrigin = $true
    readinessHandshake = $true
    atomicActivation = $true
    oneVersionRollback = $true
    boundedAudit = $true
} | ConvertTo-Json
