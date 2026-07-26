[CmdletBinding()]
param(
    [switch] $DistributionOnly
)

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

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$bridgePackage = Read-Json (Join-Path $bridgeRoot "package.json")
$bridgeManifest = Read-Json (Join-Path $bridgeRoot "manifest.json")
$releaseManifest = Read-Json (Join-Path $browserRoot "release\release-manifest.json")
$sidecarConfig = Read-Json (Join-Path $sidecarRoot "config\sidecar.json")
$domain = Get-Content -LiteralPath (Join-Path $sidecarRoot "internal\domain\types.go") -Raw
$bridgeCapabilities = Get-Content -LiteralPath (Join-Path $bridgeRoot "bridge-capabilities.js") -Raw
$sourceCatalog = Get-Content -LiteralPath (Join-Path $bridgeRoot "source-catalog.js") -Raw
$responseEvidenceAdapter = Get-Content -LiteralPath (Join-Path $bridgeRoot "x-response-evidence-adapter.js") -Raw

Assert-True ($releaseManifest.version -eq "0.7.3") "AkuBrowser release version is unexpected."
Assert-True ($releaseManifest.distribution.authorityRepository -eq "AkuBrowser") "AkuBrowser must remain the distribution authority."
Assert-True ($releaseManifest.distribution.windows.format -eq "portable-zip") "Windows preview must remain a portable ZIP."
Assert-True ($bridgePackage.version -eq $bridgeManifest.version_name) "AkuBridge package and manifest version name differ."
Assert-True ($bridgePackage.version -eq $releaseManifest.components.akuBridge.version) "AkuBridge product version drifted from the release manifest."
Assert-True ($bridgeManifest.version -eq $releaseManifest.components.akuBridge.chromeVersion) "AkuBridge Chrome version drifted from the release manifest."
Assert-True ($bridgePackage.akuRuntimeRevision -eq "source-adapters-v81") "AkuBridge development runtime revision is unexpected."
if ($DistributionOnly) {
    Assert-True ($bridgePackage.akuRuntimeRevision -eq $releaseManifest.components.akuBridge.runtimeRevision) "AkuBridge runtime revision drifted from the release manifest."
}
foreach ($source in @("x", "linkedin", "facebook")) {
    Assert-True ($sourceCatalog -match ('id:\s*"' + [regex]::Escape($source) + '"')) "AkuBridge source catalog is missing $source."
}
Assert-True ($sourceCatalog -match 'mediaEvidenceAdapterVersion:\s*"x-response-evidence-v2"') "AkuBridge X media-evidence adapter boundary is unexpected."
Assert-True ($bridgeCapabilities -match '"observe_response_media_evidence"') "AkuBridge response-evidence action is missing."
Assert-True ($bridgeCapabilities -match '"dispatch_background_commands"') "AkuBridge background Auto Update dispatch action is missing."
Assert-True ($responseEvidenceAdapter -match 'RUNTIME_REVISION\s*=\s*"x-response-evidence-v2"') "AkuBridge response-evidence runtime is unexpected."
foreach ($operation in @("HomeTimeline", "HomeLatestTimeline", "TweetDetail")) {
    Assert-True ($responseEvidenceAdapter -match [regex]::Escape($operation)) "AkuBridge response-evidence operation $operation is missing."
}
Assert-True ($sidecarConfig.reasoning.provider -eq "codex-app-server") "AkuSidecar must default to Codex App Server."
Assert-True ($sidecarConfig.preference.mode -eq "guarded_live") "High-authority guarded personalization must be the fresh default."
Assert-True ($sidecarConfig.capture.profile -eq "standard") "Standard 1x must be the fresh bounded-load default."
Assert-True ($sidecarConfig.reasoning.planning.effort -eq "high") "Acquisition planning must default to Luna High."
Assert-True ($sidecarConfig.reasoning.evaluation.effort -eq "xhigh") "Candidate evaluation must default to Luna XHigh."
Assert-True ($sidecarConfig.reasoning.semanticEvent.effort -eq "high") "Semantic resolution must default to Luna High."
Assert-True ($sidecarConfig.reasoning.aiDetection.effort -eq "high") "AI Deep Detection must default to Luna High."
Assert-True (-not (Test-Path -LiteralPath (Join-Path $sidecarRoot "package.json"))) "AkuSidecar must not contain a Node package."
Assert-True (-not (Test-Path -LiteralPath (Join-Path $browserRoot "package.json"))) "AkuBrowser must not contain a Node package."
Assert-True ($domain -match 'ApplicationVersion\s*=\s*"0\.7\.3"') "AkuSidecar version boundary is unexpected."
Assert-True ($releaseManifest.components.akuSidecar.version -eq "0.7.3") "AkuSidecar release manifest version is unexpected."
Assert-True ($releaseManifest.components.c2paTool.version -eq "0.26.60") "Pinned c2patool version is unexpected."
Assert-True ($releaseManifest.components.c2paTool.sha256 -eq "90cbcebe30250f8e8c53416d32ed86065dc04a23be86e4a2337f5cd1badfa0b7") "Pinned c2patool SHA-256 is unexpected."
Assert-True ($releaseManifest.components.c2paTool.workspaceSource -eq "AkuSidecar/runtime/dev/c2patool.exe") "Pinned c2patool workspace source is unexpected."
Assert-True ($releaseManifest.components.c2paTool.licenseSha256.mit -eq "89375a50de90d2dcaa04406086da832ad452ebcaf6ab402ef3d51b8401a67c71") "Pinned c2patool MIT license SHA-256 is unexpected."
Assert-True ($releaseManifest.components.c2paTool.licenseSha256.apache2 -eq "86bdd5dafab77451044b6fd6d2efab23e3410ce658eb097f04c04f4f54aed62f") "Pinned c2patool Apache license SHA-256 is unexpected."
Assert-True ($domain -match 'BridgeContractVersion\s*=\s*"aku-browser\.bridge\.v2"') "Bridge contract boundary is unexpected."
Assert-True ($domain -match 'DefaultAIDetectionPresentation\s*=\s*"drawer"') "AI Detector must default to Drawer."
Assert-True ($domain -match 'DefaultReasoningAcquisition\s*=\s*"luna_high"') "Acquisition profile default drifted."
Assert-True ($domain -match 'DefaultReasoningEvaluation\s*=\s*"luna_xhigh"') "Evaluation profile default drifted."
Assert-True ($domain -match 'DefaultReasoningSemantic\s*=\s*"luna_high"') "Semantic profile default drifted."
Assert-True ($domain -match 'DefaultReasoningAIDeep\s*=\s*"luna_high"') "AI Deep profile default drifted."

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

[ordered]@{
    status = "ok"
    boundary = "high-authority-go-sidecar"
    release = $releaseManifest.version
    AkuBridge = $bridgePackage.version
    AkuBridgeRuntime = $bridgePackage.akuRuntimeRevision
    AkuSidecar = "0.7.3"
    provider = $sidecarConfig.reasoning.provider
    preferenceAuthority = $sidecarConfig.preference.mode
    boundedLoadDefault = $sidecarConfig.capture.profile
} | ConvertTo-Json
