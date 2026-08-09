[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [string]$BridgeIdentityProfile = "development",
    [switch]$SkipChecks,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
$browserRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$workspaceRoot = Split-Path $browserRoot -Parent
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$registryPath = Join-Path $browserRoot "config\bridge-identities.json"
$manifestPath = Join-Path $bridgeRoot "manifest.json"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $browserRoot "artifacts\stable-candidate\prestore-windows"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith($browserRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must stay inside $browserRoot"
}

$identityJson = node (Join-Path $PSScriptRoot "bridge-extension-identity.mjs") $registryPath $manifestPath $BridgeIdentityProfile
if ($LASTEXITCODE -ne 0) { throw "Bridge development identity validation failed." }
$identity = $identityJson | ConvertFrom-Json
if ($identity.distribution -ne "unpacked" -or $identity.derivedExtensionId -ne $identity.extensionId) {
    throw "The pre-Store package requires a manifest-key-pinned unpacked identity."
}

if (-not $SkipChecks) {
    Push-Location $bridgeRoot
    try { npm run check }
    finally { Pop-Location }
}

$dirty = -not [string]::IsNullOrWhiteSpace((git -C $bridgeRoot status --porcelain))
if ($dirty -and -not $AllowDirty) {
    throw "AkuBridge must be clean. Commit the pinned identity before building the frozen pre-Store package."
}

$verificationJson = node (Join-Path $bridgeRoot "scripts\verify-extension-package.mjs")
if ($LASTEXITCODE -ne 0) { throw "Extension package verification failed." }
$verification = $verificationJson | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$stagingRoot = Join-Path $OutputDirectory "bridge-staging"
if (Test-Path -LiteralPath $stagingRoot) {
    $resolved = (Resolve-Path -LiteralPath $stagingRoot).Path
    if (-not $resolved.StartsWith($OutputDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace staging outside the output directory."
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

foreach ($entry in $verification.files) {
    $source = Join-Path $bridgeRoot $entry.path
    $target = Join-Path $stagingRoot $entry.path
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}

$packageVerificationJson = node (Join-Path $PSScriptRoot "fingerprint-extension-directory.mjs") $stagingRoot
if ($LASTEXITCODE -ne 0) { throw "Pre-Store package fingerprint failed." }
$packageVerification = $packageVerificationJson | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $stagingRoot "manifest.json") -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$manifest.key)) { throw "Pre-Store package lost manifest.key." }

$zipName = "AkuBridge-$($verification.version)-prestore-unpacked.zip"
$zipPath = Join-Path $OutputDirectory $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stagingRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$zipHash  $zipName" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ASCII

$receipt = [ordered]@{
    schemaVersion = 1
    package = $zipName
    version = $verification.version
    chromeVersion = $verification.chromeVersion
    sha256 = $zipHash
    extensionFingerprint = $packageVerification.fingerprint
    fileCount = @($packageVerification.files).Count
    identity = $identity
    source = [ordered]@{
        repository = "AkuBridge"
        commit = (git -C $bridgeRoot rev-parse HEAD).Trim()
        dirty = $dirty
    }
}
$receiptPath = Join-Path $OutputDirectory "AkuBridge-$($verification.version)-prestore-unpacked.receipt.json"
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Remove-Item -LiteralPath $stagingRoot -Recurse -Force
Write-Host "Pre-Store Bridge package: $zipPath"
Write-Host "Extension ID: $($identity.extensionId)"
Write-Host "SHA256: $zipHash"
Write-Host "Receipt: $receiptPath"
