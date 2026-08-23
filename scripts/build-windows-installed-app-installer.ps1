[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $TupleDirectory,
    [string] $OutputRoot = "",
    [string] $NsisPath = "",
    [switch] $VerifyOnly
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$nsisScript = Join-Path $browserRoot "installer\windows\installed-app.nsi"
$TupleDirectory = [IO.Path]::GetFullPath($TupleDirectory)

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON file: $Path"
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Find-NsisCompiler([string] $RequestedPath) {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $candidates += $RequestedPath }
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { $candidates += $command.Source }
    $candidates += @("C:\Program Files (x86)\NSIS\makensis.exe", "C:\Program Files\NSIS\makensis.exe")
    $selected = $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
    Assert-True (-not [string]::IsNullOrWhiteSpace($selected)) "NSIS 3 compiler was not found. Pass -NsisPath."
    return [IO.Path]::GetFullPath($selected)
}

Assert-True (Test-Path -LiteralPath $TupleDirectory -PathType Container) "Installed-app tuple directory was not found: $TupleDirectory"
Assert-True (Test-Path -LiteralPath $nsisScript -PathType Leaf) "Installed-app NSIS source is missing."

$tupleAcceptance = & (Join-Path $PSScriptRoot "test-windows-installed-app-builder.ps1") -ArtifactDirectory $TupleDirectory
if ($LASTEXITCODE -ne 0) { throw "Installed-app tuple acceptance failed before installer compilation." }
if ([string]::IsNullOrWhiteSpace(($tupleAcceptance | Out-String))) { throw "Installed-app tuple acceptance returned no evidence." }

$installManifest = Read-Json (Join-Path $TupleDirectory "install-manifest.json")
$current = Read-Json (Join-Path $TupleDirectory "runtime\current.json")
Assert-True ($installManifest.product -eq "AkuBrowser" -and $installManifest.platform -eq "windows-x64") "Tuple platform identity is invalid."
Assert-True ($installManifest.format -eq "installed-app-tuple" -and $installManifest.status -eq "staged-builder") "Tuple is not a staged installed-app artifact."
Assert-True ($installManifest.signedInstaller -eq $false -and $installManifest.installerStatus -eq "not-shipped") "Builder accepts only the explicitly unsigned, not-shipped tuple lane."
Assert-True (@($installManifest.sourceDirty).Count -eq 0) "Unified installer requires a tuple built from clean sources."
Assert-True ($installManifest.bridgeIdentity.profile -eq "production-app") "Unified installer requires production-app Bridge identity."
Assert-True ($installManifest.version -eq $current.version) "Install manifest and active pointer versions differ."
Assert-True ([string]$installManifest.bridgeIdentity.origin -match '^chrome-extension://[a-p]{32}/$') "Installed-app extension origin is invalid."

$version = [string]$installManifest.version
Assert-True ($version -match '^\d+\.\d+\.\d+$') "Installed-app installer requires a three-part numeric version."
$versionQuad = "$version.0"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $browserRoot "artifacts\installed-app-installer"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$outputFile = Join-Path $OutputRoot "AkuBrowserSetup-$version-windows-x64-unsigned.exe"

$plan = [ordered]@{
    status = if ($VerifyOnly) { "verified" } else { "ready-to-compile" }
    version = $version
    tupleDirectory = $TupleDirectory
    outputFile = $outputFile
    bridgeIdentity = [string]$installManifest.bridgeIdentity.extensionId
    signed = $false
    shipped = $false
}
if ($VerifyOnly) {
    $plan | ConvertTo-Json -Depth 4
    return
}

$compiler = Find-NsisCompiler $NsisPath
if (Test-Path -LiteralPath $outputFile) { Remove-Item -LiteralPath $outputFile -Force }
$arguments = @(
    "/V2",
    "/WX",
    "/DAPP_VERSION=$version",
    "/DVERSION_QUAD=$versionQuad",
    "/DPAYLOAD_ROOT=$TupleDirectory",
    "/DOUTPUT_FILE=$outputFile",
    "/DEXTENSION_ORIGIN=$($installManifest.bridgeIdentity.origin)",
    $nsisScript
)
& $compiler @arguments | Out-Host
if ($LASTEXITCODE -ne 0) { throw "NSIS installed-app compilation failed." }
Assert-True (Test-Path -LiteralPath $outputFile -PathType Leaf) "NSIS did not emit the expected installer."

$result = [ordered]@{
    status = "ok"
    version = $version
    tupleDirectory = $TupleDirectory
    outputFile = $outputFile
    bytes = (Get-Item -LiteralPath $outputFile).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFile).Hash.ToLowerInvariant()
    bridgeIdentity = [string]$installManifest.bridgeIdentity.extensionId
    signed = $false
    shipped = $false
}
$result | ConvertTo-Json -Depth 4
