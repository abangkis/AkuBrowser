[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ReleaseVersion,
    [Parameter(Mandatory = $true)][string] $SidecarVersion,
    [Parameter(Mandatory = $true)][string] $BrowserSha,
    [Parameter(Mandatory = $true)][string] $BridgeSha,
    [Parameter(Mandatory = $true)][string] $SidecarSha,
    [Parameter(Mandatory = $true)][string] $UpdatePublicKey,
    [Parameter(Mandatory = $true)][string] $UpdateSigningPrivateKeyPath,
    [string] $OutputRoot = "",
    [string] $C2paToolPath = "",
    [string] $NsisPath = ""
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$releaseManifestPath = Join-Path $browserRoot "release\release-manifest.json"
$identityRegistryPath = Join-Path $browserRoot "config\bridge-identities.json"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Invoke-Git([string] $Repository, [string[]] $Arguments) {
    $value = & git -C $Repository @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in $Repository" }
    return ($value | Out-String).Trim()
}

function Write-Checksum([string] $Path) {
    $name = [IO.Path]::GetFileName($Path)
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    "$hash  $name" | Set-Content -LiteralPath "$Path.sha256" -Encoding ASCII
}

function Get-AssetRecord([string] $BasePath, [string] $Path) {
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = $base + [IO.Path]::DirectorySeparatorChar
    Assert-True ($absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Artifact escaped the release kit: $absolute"
    return [ordered]@{
        path = $absolute.Substring($prefix.Length).Replace("\", "/")
        bytes = (Get-Item -LiteralPath $absolute).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolute).Hash.ToLowerInvariant()
    }
}

function Assert-ExactLane([string] $LaneRoot, [string[]] $ExpectedNames) {
    $directories = @(Get-ChildItem -LiteralPath $LaneRoot -Directory -Force)
    Assert-True ($directories.Count -eq 0) "Release lane contains an unexpected directory: $($directories.FullName -join ', ')"
    $actual = @(Get-ChildItem -LiteralPath $LaneRoot -File -Force | ForEach-Object Name | Sort-Object)
    $expected = @($ExpectedNames | Sort-Object)
    Assert-True (($actual -join "`n") -ceq ($expected -join "`n")) "Release lane differs from its allowlist. Expected: $($expected -join ', '). Actual: $($actual -join ', ')."
}

function Assert-RenderedReleaseText([string] $Path) {
    $content = Get-Content -LiteralPath $Path -Raw
    Assert-True (-not $content.Contains('$(')) "Generated release text contains an unresolved PowerShell expression: $Path"
    foreach ($character in $content.ToCharArray()) {
        $codePoint = [int][char]$character
        Assert-True ($codePoint -eq 9 -or $codePoint -eq 10 -or $codePoint -eq 13 -or $codePoint -ge 32) "Generated release text contains a control character: $Path"
    }
}

Assert-True ($IsWindows -or $env:OS -eq "Windows_NT") "Run this stable gate on Windows."
Assert-True ($ReleaseVersion -match '^\d+\.\d+\.\d+$') "ReleaseVersion must be a stable semantic version."
Assert-True ($SidecarVersion -match '^\d+\.\d+\.\d+$') "SidecarVersion must be a stable semantic version."
foreach ($sha in @($BrowserSha, $BridgeSha, $SidecarSha)) {
    Assert-True ($sha -cmatch '^[a-f0-9]{40}$') "All frozen source SHAs must be full lowercase commit IDs."
}

$repositories = [ordered]@{
    akuBrowser = [ordered]@{ path = $browserRoot; expected = $BrowserSha }
    akuBridge = [ordered]@{ path = $bridgeRoot; expected = $BridgeSha }
    akuSidecar = [ordered]@{ path = $sidecarRoot; expected = $SidecarSha }
}
foreach ($entry in $repositories.GetEnumerator()) {
    $actual = Invoke-Git $entry.Value.path @("rev-parse", "HEAD")
    Assert-True ($actual -ceq $entry.Value.expected) "$($entry.Key) HEAD differs from the frozen tuple."
    Assert-True ([string]::IsNullOrWhiteSpace((Invoke-Git $entry.Value.path @("status", "--porcelain")))) "Release source is dirty: $($entry.Value.path)"
}

$release = Read-Json $releaseManifestPath
Assert-True ($release.version -eq $ReleaseVersion) "Release manifest version differs from ReleaseVersion."
Assert-True ($release.components.akuSidecar.version -eq $SidecarVersion) "Release manifest Sidecar version differs from SidecarVersion."
Assert-True ($release.channel -eq "stable") "Release manifest must declare the stable channel."
Assert-True ($release.distribution.chromeStore.nativeRuntimeInstallers.'windows-x64'.trustState -eq "unsigned") "Windows stable gate currently requires the declared unsigned trust state."

$identities = Read-Json $identityRegistryPath
$productionIdentity = $identities.profiles.'production-store'
$acceptanceIdentity = $identities.profiles.acceptance
$offlineIdentity = $identities.profiles.'production-offline'
$developmentIdentity = $identities.profiles.development
Assert-True ($identities.schemaVersion -eq 2) "Unsupported Bridge identity registry schema."
Assert-True ($productionIdentity.distribution -eq "chrome-web-store") "Production identity must be a Chrome Web Store identity."
Assert-True ($acceptanceIdentity.distribution -eq "unpacked") "Acceptance identity must be an unpacked identity."
Assert-True ($offlineIdentity.distribution -eq "offline-bundle") "Offline production identity must be an offline-bundle identity."
$identityIds = @($developmentIdentity.extensionId, $acceptanceIdentity.extensionId, $productionIdentity.extensionId, $offlineIdentity.extensionId)
Assert-True (@($identityIds | Sort-Object -Unique).Count -eq 4) "Development, acceptance, Store, and offline identities must remain different."

$UpdateSigningPrivateKeyPath = [IO.Path]::GetFullPath($UpdateSigningPrivateKeyPath)
Assert-True (Test-Path -LiteralPath $UpdateSigningPrivateKeyPath -PathType Leaf) "Runtime-update signing key was not found."
if ([string]::IsNullOrWhiteSpace($C2paToolPath)) {
    $C2paToolPath = Join-Path $sidecarRoot "runtime\dev\c2patool.exe"
}
$C2paToolPath = [IO.Path]::GetFullPath($C2paToolPath)
Assert-True (Test-Path -LiteralPath $C2paToolPath -PathType Leaf) "Pinned Windows c2patool was not found."

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $browserRoot "artifacts\stable-$SidecarVersion-windows"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$browserPrefix = [IO.Path]::GetFullPath($browserRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
Assert-True ($OutputRoot.StartsWith($browserPrefix, [StringComparison]::OrdinalIgnoreCase)) "OutputRoot must stay inside AkuBrowser."
if (Test-Path -LiteralPath $OutputRoot) {
    Assert-True ($null -eq (Get-ChildItem -LiteralPath $OutputRoot -Force | Select-Object -First 1)) "OutputRoot must be new or empty: $OutputRoot"
    Remove-Item -LiteralPath $OutputRoot -Force
}
$finalOutputRoot = $OutputRoot
$buildingRoot = "$finalOutputRoot.building"
Assert-True (-not (Test-Path -LiteralPath $buildingRoot)) "A prior incomplete stable-gate staging directory exists: $buildingRoot"
New-Item -ItemType Directory -Path $buildingRoot | Out-Null
$OutputRoot = $buildingRoot
$publishRoot = Join-Path $OutputRoot "publish"
$acceptanceRoot = Join-Path $OutputRoot "acceptance"
New-Item -ItemType Directory -Path $publishRoot, $acceptanceRoot | Out-Null

try {
& (Join-Path $PSScriptRoot "check.ps1")
if ($LASTEXITCODE -ne 0) { throw "Cross-repository release checks failed." }

& (Join-Path $PSScriptRoot "build-windows-preview.ps1") `
    -OutputRoot $publishRoot `
    -C2paToolPath $C2paToolPath `
    -SkipValidation
if ($LASTEXITCODE -ne 0) { throw "Windows portable build failed." }
$portableZip = Join-Path $publishRoot "AkuBrowser-$ReleaseVersion-windows-x64.zip"
& (Join-Path $PSScriptRoot "test-windows-preview.ps1") -ZipPath $portableZip
if ($LASTEXITCODE -ne 0) { throw "Windows portable smoke test failed." }
$portableExpanded = Join-Path $publishRoot "AkuBrowser-$ReleaseVersion-windows-x64"
Assert-True (Test-Path -LiteralPath $portableExpanded -PathType Container) "Expanded portable validation directory is missing."
Remove-Item -LiteralPath $portableExpanded -Recurse -Force

$stableInstallerArguments = @{
    OutputRoot = $publishRoot
    C2paToolPath = $C2paToolPath
    UpdatePublicKey = $UpdatePublicKey
    UpdateSigningPrivateKeyPath = $UpdateSigningPrivateKeyPath
    UnsignedStableCandidate = $true
    SkipValidation = $true
}
if (-not [string]::IsNullOrWhiteSpace($NsisPath)) { $stableInstallerArguments.NsisPath = $NsisPath }
& (Join-Path $PSScriptRoot "build-windows-runtime-installer.ps1") @stableInstallerArguments
if ($LASTEXITCODE -ne 0) { throw "Windows stable runtime installer build failed." }

$versionedInstaller = Join-Path $publishRoot "AkuBrowserRuntimeSetup-$SidecarVersion.exe"
$stableInstallerAlias = Join-Path $publishRoot "AkuBrowserRuntimeSetup.exe"
Copy-Item -LiteralPath $versionedInstaller -Destination $stableInstallerAlias
Write-Checksum $stableInstallerAlias
$signature = Get-AuthenticodeSignature -LiteralPath $versionedInstaller
Assert-True ($signature.Status -eq "NotSigned") "Unsigned stable installer unexpectedly has signature state $($signature.Status)."

& (Join-Path $PSScriptRoot "test-windows-runtime-updater.ps1")
if ($LASTEXITCODE -ne 0) { throw "Windows runtime updater gate failed." }
& (Join-Path $PSScriptRoot "test-windows-runtime-lifecycle.ps1") -Scenario automated
if ($LASTEXITCODE -ne 0) { throw "Windows automated lifecycle gate failed." }

& (Join-Path $PSScriptRoot "build-prestore-bridge-package.ps1") `
    -OutputDirectory $acceptanceRoot `
    -BridgeIdentityProfile "acceptance" `
    -SkipChecks
if ($LASTEXITCODE -ne 0) { throw "Pre-Store Bridge package build failed." }

$localInstallerArguments = @{
    OutputRoot = $acceptanceRoot
    C2paToolPath = $C2paToolPath
    BridgeIdentityProfile = "acceptance"
    UpdatePublicKey = $UpdatePublicKey
    UnsignedLocalCandidate = $true
    SkipValidation = $true
}
if (-not [string]::IsNullOrWhiteSpace($NsisPath)) { $localInstallerArguments.NsisPath = $NsisPath }
& (Join-Path $PSScriptRoot "build-windows-runtime-installer.ps1") @localInstallerArguments
if ($LASTEXITCODE -ne 0) { throw "Pre-Store development runtime installer build failed." }

$localInstaller = Join-Path $acceptanceRoot "AkuBrowserRuntimeSetup-$SidecarVersion-unsigned-local.exe"
$localSignature = Get-AuthenticodeSignature -LiteralPath $localInstaller
Assert-True ($localSignature.Status -eq "NotSigned") "Local acceptance installer unexpectedly has signature state $($localSignature.Status)."
Copy-Item -LiteralPath (Join-Path $browserRoot "docs\windows-clean-machine-3b.md") -Destination (Join-Path $acceptanceRoot "STEP-3B-CHECKLIST.md")

Copy-Item -LiteralPath $releaseManifestPath -Destination (Join-Path $publishRoot "release-manifest.json")

$legacyAligned = (
    $release.version -eq $release.components.akuBridge.version -and
    $release.version -eq $release.components.akuSidecar.version -and
    $release.components.akuBridge.runtimeRevision -eq $release.components.akuSidecar.runtimeRevision
)
$publishNames = @(
    "AkuBrowser-$ReleaseVersion-windows-x64.zip",
    "AkuBrowser-$ReleaseVersion-windows-x64.zip.sha256",
    "AkuBrowserRuntimeSetup-$SidecarVersion.exe",
    "AkuBrowserRuntimeSetup-$SidecarVersion.exe.sha256",
    "AkuBrowserRuntimeSetup.exe",
    "AkuBrowserRuntimeSetup.exe.sha256",
    "AkuSidecar-$SidecarVersion-windows-x64.zip",
    "AkuSidecar-$SidecarVersion-windows-x64.zip.sha256",
    "AkuSidecarUpdate.json",
    "release-manifest.json"
)
if ($legacyAligned) {
    $publishNames += @(
        "AkuBrowserRuntime-$ReleaseVersion-windows-x64.zip",
        "AkuBrowserRuntime-$ReleaseVersion-windows-x64.zip.sha256",
        "AkuBrowserRuntimeUpdate.json"
    )
}
$acceptanceNames = @(
    "AkuBridge-$($release.components.akuBridge.version)-prestore-unpacked.zip",
    "AkuBridge-$($release.components.akuBridge.version)-prestore-unpacked.zip.sha256",
    "AkuBridge-$($release.components.akuBridge.version)-prestore-unpacked.receipt.json",
    "AkuBrowserRuntimeSetup-$SidecarVersion-unsigned-local.exe",
    "AkuBrowserRuntimeSetup-$SidecarVersion-unsigned-local.exe.sha256",
    "STEP-3B-CHECKLIST.md"
)
foreach ($name in @($publishNames)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $publishRoot $name) -PathType Leaf) "Publish asset is missing: $name"
}
foreach ($name in @($acceptanceNames)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $acceptanceRoot $name) -PathType Leaf) "Acceptance asset is missing: $name"
}

$acceptanceReadme = @"
# Windows 3B acceptance kit $ReleaseVersion

This folder is local test evidence only. Never upload any file from this folder to GitHub or the Chrome Web Store.

1. Extract ``AkuBridge-$($release.components.akuBridge.version)-prestore-unpacked.zip``.
2. In Chrome, enable Developer mode and Load unpacked from the extracted folder.
3. Verify extension ID ``$($acceptanceIdentity.extensionId)``.
4. Open Setup. It must offer the local installer and must not open a future GitHub release URL.
5. Run ``AkuBrowserRuntimeSetup-$SidecarVersion-unsigned-local.exe`` from this folder.
6. Return to Setup, select Check runtime, check Codex, grant intended sources, and complete one Update now.
7. Complete every item in ``STEP-3B-CHECKLIST.md`` from this folder.

Keep this complete ``acceptance/`` lane together with the root ``release-kit.json`` and verify every entry under ``acceptanceAssets`` before testing.

The publishable production identity is ``$($productionIdentity.extensionId)``; it is intentionally not used by this pre-Store kit.
"@
Write-Utf8NoBom (Join-Path $acceptanceRoot "README.md") $acceptanceReadme
Assert-RenderedReleaseText (Join-Path $acceptanceRoot "README.md")
$acceptanceNames += "README.md"

Assert-ExactLane $publishRoot $publishNames
Assert-ExactLane $acceptanceRoot $acceptanceNames

$kitReadme = @"
# AkuBrowser Windows stable release kit $ReleaseVersion

This is one release kit with three intentionally separate identity lanes:

- Store runtime installers and update manifests in ``publish/``: ``production-store`` identity.
- the portable ZIP in ``publish/``: self-contained ``production-offline`` identity and runtime.
- ``acceptance/``: manifest-key-pinned ``acceptance`` identity. Use only for clean-machine Step 3B and never upload it.

The portable ZIP under ``publish/`` is validated by automated Step 3A. It is not the Load unpacked package and is not manual Step 3B evidence.

After Windows 3B is accepted, preserve this kit unchanged, hand the same frozen source tuple to macOS, and continue the stable release checklist.
"@
Write-Utf8NoBom (Join-Path $OutputRoot "README.md") $kitReadme
Assert-RenderedReleaseText (Join-Path $OutputRoot "README.md")

$publishAssets = @($publishNames | ForEach-Object { Get-AssetRecord $OutputRoot (Join-Path $publishRoot $_) })
$acceptanceAssets = @($acceptanceNames | ForEach-Object { Get-AssetRecord $OutputRoot (Join-Path $acceptanceRoot $_) })
$kitManifest = [ordered]@{
    schemaVersion = 1
    status = "ok"
    releaseVersion = $ReleaseVersion
    sidecarVersion = $SidecarVersion
    releaseTag = "v$SidecarVersion"
    outputRoot = $finalOutputRoot
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    sourceCommits = [ordered]@{
        akuBrowser = $BrowserSha
        akuBridge = $BridgeSha
        akuSidecar = $SidecarSha
    }
    identities = [ordered]@{
        publish = [ordered]@{ profile = "production-store"; extensionId = $productionIdentity.extensionId }
        acceptance = [ordered]@{ profile = "acceptance"; extensionId = $acceptanceIdentity.extensionId }
        offline = [ordered]@{ profile = "production-offline"; extensionId = $offlineIdentity.extensionId }
    }
    signing = [ordered]@{ windowsInstaller = "unsigned"; updateManifests = "ed25519" }
    publishAssets = $publishAssets
    acceptanceAssets = $acceptanceAssets
}
Write-Utf8NoBom (Join-Path $OutputRoot "release-kit.json") ($kitManifest | ConvertTo-Json -Depth 10)
Move-Item -LiteralPath $OutputRoot -Destination $finalOutputRoot
}
catch {
    if (Test-Path -LiteralPath $buildingRoot) {
        Remove-Item -LiteralPath $buildingRoot -Recurse -Force
    }
    throw
}

$kitManifest | ConvertTo-Json -Depth 10
