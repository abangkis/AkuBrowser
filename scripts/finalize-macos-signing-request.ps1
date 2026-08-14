[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $SigningRequestZip,
    [Parameter(Mandatory = $true)][string] $MacAssetsRoot,
    [Parameter(Mandatory = $true)][string] $UpdatePublicKey,
    [Parameter(Mandatory = $true)][string] $UpdateSigningPrivateKeyPath,
    [string] $OutputRoot = "",
    [string] $GitHubAssetMapPath = "",
    [switch] $RemoveEphemeralPrivateKey
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-RelativeAsset([string] $Root, [string] $Name) {
    Assert-True (-not [IO.Path]::IsPathRooted($Name)) "Asset name must be relative: $Name"
    Assert-True (-not $Name.Contains("..")) "Asset name contains a parent traversal: $Name"
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Name))
    Assert-True ($path.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) "Asset escaped its root: $Name"
    return $path
}

function Get-SafeFilename([string] $Name, [string] $Label) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($Name)) "$Label is required."
    Assert-True (-not [IO.Path]::IsPathRooted($Name) -and -not $Name.Contains("/") -and -not $Name.Contains("\") -and $Name -ne "." -and $Name -ne "..") "$Label must be a single relative filename: $Name"
    return $Name
}

function Get-AssetRecord([string] $Root, [string] $Name) {
    $path = Get-RelativeAsset $Root $Name
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Mac asset is missing: $Name"
    return [ordered]@{
        name = $Name
        bytes = (Get-Item -LiteralPath $path).Length
        sha256 = Get-Sha256 $path
    }
}

function Invoke-SignTool([string[]] $Arguments) {
    $output = & go -C (Join-Path $browserRoot "installer\windows") run .\cmd\sign-update-manifest @Arguments
    if ($LASTEXITCODE -ne 0) { throw "sign-update-manifest failed: $($Arguments -join ' ')" }
    return ($output | Out-String).Trim()
}

Assert-True ($IsWindows -or $env:OS -eq "Windows_NT") "Run the macOS signing finalizer on Windows."
Assert-True (Test-Path -LiteralPath $SigningRequestZip -PathType Leaf) "Signing request ZIP was not found."
Assert-True (Test-Path -LiteralPath $MacAssetsRoot -PathType Container) "Mac asset directory was not found."
Assert-True (Test-Path -LiteralPath $UpdateSigningPrivateKeyPath -PathType Leaf) "Runtime update signing key was not found."

try {
    $decodedPublicKey = [Convert]::FromBase64String($UpdatePublicKey)
} catch {
    throw "UpdatePublicKey must be valid base64."
}
Assert-True ($decodedPublicKey.Length -eq 32) "UpdatePublicKey must contain a 32-byte Ed25519 public key."

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $releaseVersionForDefault = "candidate"
    $OutputRoot = Join-Path $browserRoot "artifacts\stable-$releaseVersionForDefault-macos-final"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$browserPrefix = [IO.Path]::GetFullPath($browserRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
Assert-True ($OutputRoot.StartsWith($browserPrefix, [StringComparison]::OrdinalIgnoreCase)) "OutputRoot must stay inside AkuBrowser."
if (Test-Path -LiteralPath $OutputRoot) {
    Assert-True ($null -eq (Get-ChildItem -LiteralPath $OutputRoot -Force | Select-Object -First 1)) "OutputRoot must be new or empty: $OutputRoot"
    Remove-Item -LiteralPath $OutputRoot -Force
}

$requestRoot = Join-Path ([IO.Path]::GetTempPath()) ("akubrowser-macos-signing-request-" + [guid]::NewGuid().ToString("N"))
$buildingRoot = "$OutputRoot.building"
Assert-True (-not (Test-Path -LiteralPath $buildingRoot)) "A prior incomplete finalizer staging directory exists: $buildingRoot"
New-Item -ItemType Directory -Path $requestRoot, $buildingRoot | Out-Null
$privateKeyFullPath = [IO.Path]::GetFullPath($UpdateSigningPrivateKeyPath)

try {
    Expand-Archive -LiteralPath (Resolve-Path -LiteralPath $SigningRequestZip) -DestinationPath (Join-Path $requestRoot "request") -Force
    $requestDirectory = Join-Path $requestRoot "request"
    $requestMetadata = Read-Json (Join-Path $requestDirectory "signing-request.json")
    Assert-True ($requestMetadata.schemaVersion -eq 1 -and $requestMetadata.kind -eq "AkuBrowser.macos-signing-request" -and $requestMetadata.status -eq "unsigned") "Signing request identity is invalid."
    Assert-True ($requestMetadata.publicKey.base64 -eq $UpdatePublicKey) "Signing request public key differs from the pinned Windows key."
    Assert-True ($requestMetadata.publicKey.keyId -eq "aku-runtime-stable-v1" -and $requestMetadata.publicKey.algorithm -eq "Ed25519") "Signing request key identity is invalid."
    Assert-True ([string]$requestMetadata.releaseVersion -match '^\d+\.\d+\.\d+$') "Signing request release version is invalid."
    Assert-True ([string]$requestMetadata.sidecarVersion -match '^\d+\.\d+\.\d+$') "Signing request Sidecar version is invalid."
    foreach ($property in @("akuBrowser", "akuBridge", "akuSidecar")) {
        Assert-True ([string]$requestMetadata.sourceCommits.$property -cmatch '^[a-f0-9]{40}$') "Signing request source SHA is invalid: $property"
    }
    $portableProvenance = Read-Json (Join-Path $requestDirectory "portable-artifact-manifest.json")
    foreach ($property in @("akuBrowser", "akuBridge", "akuSidecar")) {
        Assert-True ([string]$portableProvenance.sourceCommits.$property -ceq [string]$requestMetadata.sourceCommits.$property) "Portable artifact provenance differs from the request: $property"
    }
    Assert-True (@($portableProvenance.sourceDirty).Count -eq 0) "Portable artifact records dirty release sources."

    $requestArchiveHash = Get-Sha256 (Resolve-Path -LiteralPath $SigningRequestZip)
    $assetMap = @{}
    if (-not [string]::IsNullOrWhiteSpace($GitHubAssetMapPath)) {
        Assert-True (Test-Path -LiteralPath $GitHubAssetMapPath -PathType Leaf) "GitHub asset map was not found."
        $assetMapJson = Read-Json $GitHubAssetMapPath
        foreach ($property in $assetMapJson.PSObject.Properties) { $assetMap[$property.Name] = [string]$property.Value }
    }

    $publishAssets = @()
    foreach ($expected in @($requestMetadata.publishAssets)) {
        $assetName = Get-SafeFilename ([string]$expected.name) "Publish asset name"
        $actual = Get-AssetRecord $MacAssetsRoot $assetName
        Assert-True ($actual.bytes -eq [int64]$expected.bytes -and $actual.sha256 -eq [string]$expected.sha256) "Mac asset digest differs from the signing request: $($expected.name)"
        $publishAssets += $actual
    }

    $signedRoot = Join-Path $buildingRoot "publish"
    New-Item -ItemType Directory -Path $signedRoot | Out-Null
    foreach ($asset in $publishAssets) {
        Copy-Item -LiteralPath (Get-RelativeAsset $MacAssetsRoot $asset.name) -Destination (Join-Path $signedRoot $asset.name)
    }

    $signedManifestRecords = @()
    foreach ($expectedManifest in @($requestMetadata.unsignedManifests)) {
        $inputName = Get-SafeFilename ([string]$expectedManifest.inputName) "Unsigned manifest input name"
        $signedName = Get-SafeFilename ([string]$expectedManifest.outputName) "Signed manifest output name"
        $expectedArtifactName = Get-SafeFilename ([string]$expectedManifest.artifactName) "Unsigned manifest artifact name"
        $unsignedPath = Get-RelativeAsset $requestDirectory $inputName
        Assert-True (Test-Path -LiteralPath $unsignedPath -PathType Leaf) "Unsigned manifest is missing from request: $inputName"
        Assert-True ((Get-Item -LiteralPath $unsignedPath).Length -eq [int64]$expectedManifest.bytes -and (Get-Sha256 $unsignedPath) -eq [string]$expectedManifest.sha256) "Unsigned manifest digest differs from request: $inputName"

        $signedPath = Get-RelativeAsset $signedRoot $signedName
        $derivedPublicKey = Invoke-SignTool @(
            "-manifest", $unsignedPath,
            "-private-key", $privateKeyFullPath,
            "-output", $signedPath
        )
        Assert-True ($derivedPublicKey -eq $UpdatePublicKey) "Derived public key differs from the pinned key for $signedName"
        [void](Invoke-SignTool @("-verify-signed", $signedPath, "-public-key", $UpdatePublicKey))

        $comparisonScript = @'
import fs from "node:fs";
const [unsignedPath, signedPath] = process.argv.slice(1);
const unsigned = JSON.parse(fs.readFileSync(unsignedPath, "utf8"));
const signed = JSON.parse(fs.readFileSync(signedPath, "utf8"));
const { signature, ...signedUnsigned } = signed;
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  return value;
};
if (!signature || JSON.stringify(stable(unsigned)) !== JSON.stringify(stable(signedUnsigned))) {
  throw new Error("signed manifest does not preserve the exact unsigned payload");
}
'@
        & node --input-type=module -e $comparisonScript $unsignedPath $signedPath
        if ($LASTEXITCODE -ne 0) { throw "signed manifest does not preserve the exact unsigned payload: $signedName" }

        $artifactName = $expectedArtifactName
        $artifactPath = Get-RelativeAsset $signedRoot $artifactName
        Assert-True (Test-Path -LiteralPath $artifactPath -PathType Leaf) "Signed manifest artifact is missing: $artifactName"
        $signedManifest = Read-Json $signedPath
        Assert-True ([string]$signedManifest.artifact.url -match ("/" + [regex]::Escape($artifactName) + "$") -and [int64]$signedManifest.artifact.size -eq (Get-Item -LiteralPath $artifactPath).Length -and [string]$signedManifest.artifact.sha256 -eq (Get-Sha256 $artifactPath)) "Signed manifest artifact binding changed: $signedName"
        $signedManifestRecords += [ordered]@{
            inputName = [string]$expectedManifest.inputName
            outputName = $signedName
            schemaVersion = [int]$expectedManifest.schemaVersion
            unsignedSha256 = [string]$expectedManifest.sha256
            signedSha256 = Get-Sha256 $signedPath
            artifactName = $artifactName
            githubAssetId = if ($assetMap.ContainsKey($artifactName)) { $assetMap[$artifactName] } else { $null }
        }
    }

    $releaseManifest = Join-Path $requestDirectory "release-manifest.json"
    Assert-True (Test-Path -LiteralPath $releaseManifest -PathType Leaf) "Release manifest is missing from request."
    Copy-Item -LiteralPath $releaseManifest -Destination (Join-Path $signedRoot "release-manifest.json")
    $receiptName = "AkuBrowser-$($requestMetadata.releaseVersion)-macos-signing-receipt.json"
    $receiptAssets = @($publishAssets | ForEach-Object {
        [ordered]@{
            name = $_.name
            bytes = $_.bytes
            sha256 = $_.sha256
            githubAssetId = if ($assetMap.ContainsKey($_.name)) { $assetMap[$_.name] } else { $null }
        }
    })
    $receipt = [ordered]@{
        schemaVersion = 1
        kind = "AkuBrowser.macos-signing-receipt"
        status = "signed"
        requestArchive = [IO.Path]::GetFileName((Resolve-Path -LiteralPath $SigningRequestZip))
        requestSha256 = $requestArchiveHash
        releaseVersion = [string]$requestMetadata.releaseVersion
        sidecarVersion = [string]$requestMetadata.sidecarVersion
        releaseTag = [string]$requestMetadata.releaseTag
        sourceCommits = $requestMetadata.sourceCommits
        publicKey = $requestMetadata.publicKey
        assetRecords = $receiptAssets
        signedManifests = $signedManifestRecords
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    }
    Write-Utf8NoBom (Join-Path $signedRoot $receiptName) ($receipt | ConvertTo-Json -Depth 12)

    $finalKit = [ordered]@{
        schemaVersion = 1
        status = "ok"
        releaseVersion = [string]$requestMetadata.releaseVersion
        sidecarVersion = [string]$requestMetadata.sidecarVersion
        releaseTag = [string]$requestMetadata.releaseTag
        sourceCommits = $requestMetadata.sourceCommits
        signing = [ordered]@{ macosInstaller = "unsigned"; updateManifests = "ed25519"; privateKeyLocation = "windows-only" }
        publishAssets = @((Get-ChildItem -LiteralPath $signedRoot -File | Sort-Object Name | ForEach-Object {
            [ordered]@{ path = "publish/$($_.Name)"; bytes = $_.Length; sha256 = Get-Sha256 $_.FullName }
        }))
        signingReceipt = "publish/$receiptName"
    }
    Write-Utf8NoBom (Join-Path $buildingRoot "release-kit.json") ($finalKit | ConvertTo-Json -Depth 12)
    Write-Utf8NoBom (Join-Path $buildingRoot "README.md") "# AkuBrowser macOS finalized release kit $($requestMetadata.releaseVersion)`r`n`r`nThe publish lane contains the finalized Mac assets and Windows signing receipt. The private key remained on Windows.`r`n"

    Move-Item -LiteralPath $buildingRoot -Destination $OutputRoot
    $finalKit | ConvertTo-Json -Depth 12
}
catch {
    if (Test-Path -LiteralPath $buildingRoot) { Remove-Item -LiteralPath $buildingRoot -Recurse -Force }
    throw
}
finally {
    if (Test-Path -LiteralPath $requestRoot) { Remove-Item -LiteralPath $requestRoot -Recurse -Force }
    if ($RemoveEphemeralPrivateKey -and (Test-Path -LiteralPath $privateKeyFullPath -PathType Leaf)) {
        $length = (Get-Item -LiteralPath $privateKeyFullPath).Length
        if ($length -gt 0) { [IO.File]::WriteAllBytes($privateKeyFullPath, [byte[]]::new($length)) }
        Remove-Item -LiteralPath $privateKeyFullPath -Force
    }
}
