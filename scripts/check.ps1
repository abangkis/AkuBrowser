[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$supervisorRoot = Join-Path $workspaceRoot "AkuSupervisor"
$cacheRoot = Join-Path $workspaceRoot ".go-cache"
$env:GOCACHE = Join-Path $cacheRoot "build"
$env:GOMODCACHE = Join-Path $cacheRoot "mod"
$env:GOTMPDIR = Join-Path $cacheRoot "tmp"
foreach ($directory in @($env:GOCACHE, $env:GOMODCACHE, $env:GOTMPDIR)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$bridgePackage = Read-Json (Join-Path $bridgeRoot "package.json")
$bridgeManifest = Read-Json (Join-Path $bridgeRoot "manifest.json")
$sidecarConfig = Read-Json (Join-Path $sidecarRoot "config\sidecar.json")
$supervisorProfile = Read-Json (Join-Path $supervisorRoot "config\akuworkspace.services.json")
$domain = Get-Content -LiteralPath (Join-Path $sidecarRoot "internal\domain\types.go") -Raw

Assert-True ($bridgePackage.version -eq $bridgeManifest.version) "AkuBridge package and manifest versions differ."
Assert-True ($bridgePackage.akuRuntimeRevision -eq "source-fidelity-v56") "AkuBridge runtime revision is unexpected."
Assert-True ($sidecarConfig.reasoning.provider -eq "codex-app-server") "AkuSidecar must default to Codex App Server."
Assert-True ($sidecarConfig.preference.mode -eq "guarded_live") "High-authority guarded personalization must be the fresh default."
Assert-True ($sidecarConfig.capture.profile -eq "standard") "Standard 1x must be the fresh bounded-load default."
Assert-True (-not (Test-Path -LiteralPath (Join-Path $sidecarRoot "package.json"))) "AkuSidecar must not contain a Node package."
Assert-True (-not (Test-Path -LiteralPath (Join-Path $browserRoot "package.json"))) "AkuBrowser must not contain a Node package."
Assert-True ($domain -match 'ApplicationVersion\s*=\s*"1\.0\.0-dev\.11"') "AkuSidecar version boundary is unexpected."
Assert-True ($domain -match 'BridgeContractVersion\s*=\s*"aku-browser\.bridge\.v2"') "Bridge contract boundary is unexpected."

$schemas = @(
    "acquisition-plan.schema.json",
    "reasoning-result.schema.json",
    "semantic-event-resolution.schema.json",
    "ai-deep-detection.schema.json",
    "calibration-session.schema.json",
    "calibration-label.schema.json",
    "calibration-profile-snapshot.schema.json"
)
foreach ($schema in $schemas) {
    $canonical = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $browserRoot "contracts\$schema")).Hash
    $runtime = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $sidecarRoot "schemas\$schema")).Hash
    Assert-True ($canonical -eq $runtime) "$schema drifted between AkuBrowser and AkuSidecar."
}

$supervised = $supervisorProfile.services.akusidecar
Assert-True ($supervised.command -eq (Join-Path $sidecarRoot "runtime\dev\aku-sidecar.exe")) "AkuSupervisor does not own the direct Go binary."
Assert-True ($supervised.health.expect.version -eq "1.0.0-dev.11") "AkuSupervisor expects the wrong AkuSidecar version."
Assert-True ($supervised.health.expect.runtime -eq "go") "AkuSupervisor does not require the Go runtime."

Push-Location $sidecarRoot
try {
    & go test -p 1 ./...
    if ($LASTEXITCODE -ne 0) { throw "AkuSidecar tests failed." }
}
finally { Pop-Location }

Push-Location $bridgeRoot
try {
    & npm run check
    if ($LASTEXITCODE -ne 0) { throw "AkuBridge checks failed." }
}
finally { Pop-Location }

Push-Location $supervisorRoot
try {
    & cargo test --test schema_contract
    if ($LASTEXITCODE -ne 0) { throw "AkuSupervisor schema contract failed." }
}
finally { Pop-Location }

[ordered]@{
    status = "ok"
    boundary = "high-authority-go-sidecar"
    AkuBridge = $bridgePackage.version
    AkuBridgeRuntime = $bridgePackage.akuRuntimeRevision
    AkuSidecar = "1.0.0-dev.11"
    provider = $sidecarConfig.reasoning.provider
    preferenceAuthority = $sidecarConfig.preference.mode
    boundedLoadDefault = $sidecarConfig.capture.profile
} | ConvertTo-Json
