[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [switch]$SkipChecks
)

$ErrorActionPreference = "Stop"
$browserRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$workspaceRoot = Split-Path $browserRoot -Parent
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$identityRegistryPath = Join-Path $browserRoot "config\bridge-identities.json"

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $browserRoot "artifacts\chrome-store"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith($browserRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must stay inside $browserRoot"
}

if (-not $SkipChecks) {
    Push-Location $bridgeRoot
    try { npm run check }
    finally { Pop-Location }
}

$verificationJson = node (Join-Path $bridgeRoot "scripts\verify-extension-package.mjs")
if ($LASTEXITCODE -ne 0) { throw "Extension package verification failed." }
$verification = $verificationJson | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$stagingRoot = Join-Path $OutputDirectory "staging"
if (Test-Path -LiteralPath $stagingRoot) {
    $resolvedStaging = (Resolve-Path -LiteralPath $stagingRoot).Path
    if (-not $resolvedStaging.StartsWith($OutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace staging path outside the output directory."
    }
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

foreach ($entry in $verification.files) {
    $source = Join-Path $bridgeRoot $entry.path
    $target = Join-Path $stagingRoot $entry.path
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}

# The Store package receives both its keyless manifest and explicit deployment
# lifecycle from the registry-selected Store profile.
$projectionJson = node (Join-Path $PSScriptRoot "project-bridge-package-identity.mjs") $identityRegistryPath $stagingRoot "production-store"
if ($LASTEXITCODE -ne 0) { throw "Chrome Web Store identity projection failed." }
$projection = ($projectionJson | Out-String) | ConvertFrom-Json

$packageVerificationJson = node (Join-Path $PSScriptRoot "fingerprint-extension-directory.mjs") $stagingRoot
if ($LASTEXITCODE -ne 0) { throw "Packaged extension fingerprint failed." }
$packageVerification = $packageVerificationJson | ConvertFrom-Json

$zipName = "AkuBrowser-$($verification.version)-chrome-web-store.zip"
$zipPath = Join-Path $OutputDirectory $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stagingRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $actualFiles = @($archive.Entries |
        Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
        ForEach-Object { $_.FullName.Replace("\", "/") } |
        Sort-Object)
}
finally { $archive.Dispose() }
$expectedFiles = @($packageVerification.files.path | Sort-Object)
if (Compare-Object $expectedFiles $actualFiles) {
    throw "ZIP contents differ from the verified extension closure."
}

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$bridgeCommit = (git -C $bridgeRoot rev-parse HEAD).Trim()
$bridgeDirty = -not [string]::IsNullOrWhiteSpace((git -C $bridgeRoot status --porcelain))
$receipt = [ordered]@{
    schemaVersion = 1
    package = $zipName
    version = $verification.version
    chromeVersion = $verification.chromeVersion
    sha256 = $zipHash
    extensionFingerprint = $packageVerification.fingerprint
    sourceFingerprint = $verification.fingerprint
    developmentKeyRemoved = $true
    identity = $projection
    fileCount = $expectedFiles.Count
    source = @{
        repository = "AkuBridge"
        commit = $bridgeCommit
        dirty = $bridgeDirty
    }
}
$receiptPath = Join-Path $OutputDirectory "AkuBrowser-$($verification.version)-chrome-web-store.receipt.json"
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Remove-Item -LiteralPath $stagingRoot -Recurse -Force
Write-Host "Chrome Web Store package: $zipPath"
Write-Host "SHA256: $zipHash"
Write-Host "Receipt: $receiptPath"
