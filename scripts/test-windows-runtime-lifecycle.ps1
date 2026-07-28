[CmdletBinding()]
param(
    [ValidateSet(
        "automated",
        "first_install",
        "chrome_restart",
        "pc_restart",
        "sidecar_recovery",
        "extension_update",
        "runtime_repair",
        "uninstalled",
        "reinstalled"
    )]
    [string] $Scenario = "automated",
    [string] $ExtensionId = "",
    [string] $InstallerPath = "",
    [string] $ObservedState = "",
    [string] $DataMarkerPath = "",
    [string] $EvidencePath = ""
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$acceptancePath = Join-Path $browserRoot "acceptance\windows-runtime-lifecycle.json"
$programRoot = Join-Path $env:LOCALAPPDATA "Programs\AkuBrowser"
$dataRoot = Join-Path $env:LOCALAPPDATA "AkuBrowser\data"
$nativeRegistryPath = "Software\Google\Chrome\NativeMessagingHosts\com.akubrowser.runtime"
$uninstallRegistryPath = "Software\Microsoft\Windows\CurrentVersion\Uninstall\AkuBrowserRuntime"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-RegistryDefault([string] $Path) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    if ($null -eq $key) { return $null }
    try { return $key.GetValue("") }
    finally { $key.Dispose() }
}

function Registry-KeyExists([string] $Path) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    if ($null -eq $key) { return $false }
    $key.Dispose()
    return $true
}

function Assert-Installed([string] $ExpectedExtensionId) {
    $manifestPath = Read-RegistryDefault $nativeRegistryPath
    Assert-True (-not [string]::IsNullOrWhiteSpace($manifestPath)) "Native Messaging registration is missing."
    $expectedManifest = Join-Path $programRoot "host\com.akubrowser.runtime.json"
    Assert-True ([IO.Path]::GetFullPath($manifestPath) -eq [IO.Path]::GetFullPath($expectedManifest)) "Native Messaging registration points outside the stable host path."
    Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) "Native Messaging manifest is missing."
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-True ($manifest.name -eq "com.akubrowser.runtime") "Native Messaging host identity is invalid."
    Assert-True ($manifest.allowed_origins.Count -eq 1) "Native Messaging manifest must contain one exact Store origin."
    Assert-True ($manifest.allowed_origins[0] -eq "chrome-extension://$ExpectedExtensionId/") "Native Messaging Store origin differs from the acceptance input."
    Assert-True (Registry-KeyExists $uninstallRegistryPath) "Windows uninstall/repair registration is missing."
    Assert-True (Test-Path -LiteralPath (Join-Path $programRoot "runtime\current.json") -PathType Leaf) "Active runtime metadata is missing."
}

function Read-Health {
    try {
        return Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:11122/api/health" -TimeoutSec 3
    }
    catch {
        throw "AkuBrowser health endpoint is not ready: $($_.Exception.Message)"
    }
}

function Assert-Ready {
    $health = Read-Health
    Assert-True ($health.status -eq "ok") "AkuBrowser health status is not ok."
    Assert-True ($health.version -eq "0.7.4") "AkuBrowser runtime version is unexpected."
    Assert-True ($health.runtime -eq "go") "AkuBrowser runtime implementation is unexpected."
    Assert-True ($health.bridgeContractVersion -eq "aku-browser.bridge.v2") "AkuBrowser Bridge contract is unexpected."
}

function Assert-ObservedState([string] $Expected) {
    Assert-True ($ObservedState -eq $Expected) "Observed extension state must be '$Expected', got '$ObservedState'."
}

$acceptance = Get-Content -LiteralPath $acceptancePath -Raw | ConvertFrom-Json
Assert-True ($acceptance.schemaVersion -eq 1 -and $acceptance.version -eq "0.7.4") "Lifecycle acceptance manifest is incompatible."

if ($Scenario -eq "automated") {
    & (Join-Path $browserRoot "scripts\check.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Cross-repository lifecycle checks failed." }
    Push-Location $bridgeRoot
    try {
        & npm run package:verify
        if ($LASTEXITCODE -ne 0) { throw "Store extension package verification failed." }
    }
    finally { Pop-Location }
    [ordered]@{
        status = "ok"
        scenario = "automated"
        scenarios = @($acceptance.scenarios.id)
        cleanMachineExecuted = $false
    } | ConvertTo-Json -Depth 5
    exit 0
}

Assert-True ($ExtensionId -match "^[a-p]{32}$") "A real 32-character Chrome Web Store extension ID is required."
Assert-True (@(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "abcdefghijklmnopabcdefghijklmnop"
) -notcontains $ExtensionId) "Clean-machine acceptance rejects placeholder extension IDs."
Assert-True ($ExtensionId -notmatch '^([a-p])\1{31}$') "Clean-machine acceptance rejects repeated-character placeholder extension IDs."
$facts = [ordered]@{
    schemaVersion = 1
    scenario = $Scenario
    observedAt = (Get-Date).ToUniversalTime().ToString("o")
    extensionId = $ExtensionId
    dataRootPresent = (Test-Path -LiteralPath $dataRoot -PathType Container)
}
if (-not [string]::IsNullOrWhiteSpace($DataMarkerPath)) {
    $absoluteMarker = [IO.Path]::GetFullPath($DataMarkerPath)
    $absoluteDataRoot = [IO.Path]::GetFullPath($dataRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    Assert-True ($absoluteMarker.StartsWith(
        $absoluteDataRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) "Data marker must remain inside the AkuBrowser user-data root."
    Assert-True (Test-Path -LiteralPath $absoluteMarker -PathType Leaf) "Data-preservation marker is missing."
    $facts["dataMarkerSha256"] = (Get-FileHash -Algorithm SHA256 -LiteralPath $absoluteMarker).Hash.ToLowerInvariant()
}

switch ($Scenario) {
    "first_install" {
        Assert-True (-not (Registry-KeyExists $nativeRegistryPath)) "First-install checkpoint already has a native host registration."
        Assert-True (Test-Path -LiteralPath $InstallerPath -PathType Leaf) "Signed production installer path is required."
        $signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
        Assert-True ($signature.Status -eq "Valid") "Production installer Authenticode signature is not valid."
        Assert-ObservedState "runtime_install_required"
        $facts["installerSha256"] = (Get-FileHash -Algorithm SHA256 -LiteralPath $InstallerPath).Hash.ToLowerInvariant()
        $facts["signatureStatus"] = $signature.Status.ToString()
    }
    "uninstalled" {
        Assert-True (-not [string]::IsNullOrWhiteSpace($DataMarkerPath)) "Uninstall acceptance requires a durable data marker."
        Assert-True (-not (Registry-KeyExists $nativeRegistryPath)) "Native Messaging registration survived uninstall."
        Assert-True (-not (Registry-KeyExists $uninstallRegistryPath)) "Windows uninstall registration survived uninstall."
        Assert-True (Test-Path -LiteralPath $dataRoot -PathType Container) "User data root did not survive uninstall."
        Assert-ObservedState "runtime_install_required"
    }
    default {
        if ($Scenario -eq "reinstalled") {
            Assert-True (-not [string]::IsNullOrWhiteSpace($DataMarkerPath)) "Reinstall acceptance requires the original durable data marker."
        }
        Assert-Installed $ExtensionId
        Assert-Ready
        Assert-ObservedState "runtime_ready"
    }
}

$result = [ordered]@{
    status = "ok"
    cleanMachineExecuted = $true
    evidence = $facts
}
$json = $result | ConvertTo-Json -Depth 6
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
    $absoluteEvidence = [IO.Path]::GetFullPath($EvidencePath)
    $parent = Split-Path -Parent $absoluteEvidence
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($absoluteEvidence, $json, [Text.UTF8Encoding]::new($false))
}
$json
