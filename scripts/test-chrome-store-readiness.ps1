[CmdletBinding()]
param([switch]$SkipExtensionChecks)

$ErrorActionPreference = "Stop"
$browserRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$workspaceRoot = Split-Path $browserRoot -Parent
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$manifest = Get-Content (Join-Path $bridgeRoot "manifest.json") -Raw | ConvertFrom-Json
$release = Get-Content (Join-Path $browserRoot "release\release-manifest.json") -Raw | ConvertFrom-Json
$sidecarConfig = Get-Content (Join-Path $workspaceRoot "AkuSidecar\config\sidecar.json") -Raw | ConvertFrom-Json
$storeId = [string]$release.distribution.chromeStore.extensionId
$storeOrigin = "chrome-extension://$storeId/"
if ($storeId -notmatch '^[a-p]{32}$') { throw "Release manifest must contain the exact Store extension ID." }
if ($release.distribution.chromeStore.extensionOrigin -ne $storeOrigin) { throw "Release Store ID and origin differ." }
if (@($sidecarConfig.bridge.trustedExtensionOrigins).Count -ne 1 -or $sidecarConfig.bridge.trustedExtensionOrigins[0] -ne $storeOrigin) {
    throw "AkuSidecar production Bridge allowlist differs from the release Store origin."
}

if ($manifest.manifest_version -ne 3) { throw "Manifest V3 is required." }
if ($manifest.name -ne "AkuBrowser") { throw "Public manifest name must be AkuBrowser." }
if ($manifest.permissions -contains "tabs") { throw "The unused tabs permission must stay absent." }
if ($manifest.optional_host_permissions.Count -ne 4) { throw "Expected four independently revocable source origins." }
if ($manifest.content_scripts.Count -ne 1) { throw "Social scripts must not be statically registered." }

function Read-PngDimensions([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 24 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80) {
        throw "$Path is not a valid PNG."
    }
    $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
    $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
    return @($width, $height)
}

foreach ($size in 16, 32, 48, 128) {
    $iconPath = Join-Path $bridgeRoot "icons\icon-$size.png"
    $dimensions = Read-PngDimensions $iconPath
    if ($dimensions[0] -ne $size -or $dimensions[1] -ne $size) {
        throw "$iconPath must be ${size}x${size}."
    }
}
$storeIcon = Read-PngDimensions (Join-Path $browserRoot "store\assets\store-icon-128.png")
if ($storeIcon[0] -ne 128 -or $storeIcon[1] -ne 128) { throw "Store icon must be 128x128." }

$requiredFiles = @(
    "PRIVACY.md",
    "store\listing\id-ID.md",
    "store\listing\en-US.md",
    "store\privacy-declarations.json",
    "store\permission-justification.md",
    "store\reviewer-instructions.md",
    "store\submission-checklist.md"
)
foreach ($relative in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $browserRoot $relative))) {
        throw "Missing Store readiness asset: $relative"
    }
}

$privacy = Get-Content (Join-Path $browserRoot "PRIVACY.md") -Raw
foreach ($phrase in @("no social-domain permission is granted by", "confirm the selection", "does not sell user data", "Limited Use")) {
    if (-not $privacy.Contains($phrase)) { throw "Privacy policy is missing required disclosure: $phrase" }
}
$declarations = Get-Content (Join-Path $browserRoot "store\privacy-declarations.json") -Raw | ConvertFrom-Json
if ($declarations.sold -or $declarations.advertising -or $declarations.remoteCode) {
    throw "Store privacy declarations conflict with the reviewed package."
}
if (-not $declarations.dataCategories.websiteContent -or
    -not $declarations.dataCategories.webHistory -or
    -not $declarations.dataCategories.userActivity) {
    throw "Website content, web history, and user activity must be declared."
}

$screenshots = @(Get-ChildItem (Join-Path $browserRoot "store\assets") -File |
    Where-Object { $_.Name -match '^screenshot-.*\.(?:png|jpe?g)$' })
if ($screenshots.Count -lt 1) { throw "At least one current Store screenshot is required." }
Add-Type -AssemblyName System.Drawing
foreach ($screenshot in $screenshots) {
    $image = [System.Drawing.Image]::FromFile($screenshot.FullName)
    try {
        if ($image.Width -ne 1280 -or $image.Height -ne 800) {
            throw "$($screenshot.Name) must be 1280x800."
        }
    }
    finally {
        $image.Dispose()
    }
}

& (Join-Path $PSScriptRoot "build-chrome-store-package.ps1") -SkipChecks:$SkipExtensionChecks
if ($LASTEXITCODE -ne 0) { throw "Chrome Web Store package build failed." }
Write-Host "Chrome Web Store readiness checks passed."
