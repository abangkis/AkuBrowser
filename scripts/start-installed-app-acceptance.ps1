[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $TupleDirectory,
    [Parameter(Mandatory = $true)] [string] $AcceptanceRoot,
    [switch] $PlanOnly,
    [switch] $AllowForeground,
    [ValidateRange(1, 65535)] [int] $DiagnosticPort = 0,
    [switch] $ChromiumStartupDiagnostics
)

$ErrorActionPreference = "Stop"
if (-not $PlanOnly -and -not $AllowForeground) {
    throw "This acceptance run opens pinned Chromium in the foreground. Pass -AllowForeground only after the user approves the visual test."
}

$browserRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $browserRoot "build")).TrimEnd([IO.Path]::DirectorySeparatorChar)
$acceptanceRoot = [IO.Path]::GetFullPath($AcceptanceRoot)
$tupleRoot = [IO.Path]::GetFullPath($TupleDirectory)
$prefix = $allowedRoot + [IO.Path]::DirectorySeparatorChar
if (-not [IO.Path]::GetFullPath((Split-Path -Parent $acceptanceRoot)).Equals($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "AcceptanceRoot must be a direct child of AkuBrowser/build."
}
if (-not $tupleRoot.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "TupleDirectory must be under AkuBrowser/build."
}
if ($tupleRoot.StartsWith($acceptanceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    $acceptanceRoot.StartsWith($tupleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "AcceptanceRoot and TupleDirectory must be separate directories."
}
if ((Get-Item -LiteralPath $allowedRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw "AkuBrowser/build must not be a reparse point."
}
if ((Test-Path -LiteralPath $acceptanceRoot) -and ((Get-Item -LiteralPath $acceptanceRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "AcceptanceRoot must not be a reparse point."
}
if (-not (Test-Path -LiteralPath $tupleRoot -PathType Container)) {
    throw "The installed-app test tuple does not exist: $tupleRoot"
}
$launcher = Join-Path $tupleRoot "AkuBrowserLauncher.exe"
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "The installed-app test launcher does not exist: $launcher"
}
if ($DiagnosticPort -eq 11122) {
    throw "DiagnosticPort must not overlap the production Bridge port 11122."
}

$isolatedLocalAppData = Join-Path $acceptanceRoot "LocalAppData"
$realLocalAppData = [IO.Path]::GetFullPath([Environment]::GetFolderPath("LocalApplicationData"))
if ($isolatedLocalAppData.StartsWith($realLocalAppData + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The isolated LOCALAPPDATA path overlaps the real user profile."
}

$digest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($acceptanceRoot.ToLowerInvariant()))
$namespace = "AkuBrowserTest-" + [Convert]::ToHexString($digest).Substring(0, 16).ToLowerInvariant()
if ($PlanOnly) {
    [ordered]@{
        status = "planned"
        tupleDirectory = $tupleRoot
        acceptanceRoot = $acceptanceRoot
        isolatedLocalAppData = $isolatedLocalAppData
        credentialNamespace = $namespace
        diagnosticPort = $DiagnosticPort
        bridgeLoaded = ($DiagnosticPort -eq 0)
        chromiumStartupDiagnostics = [bool]$ChromiumStartupDiagnostics
        wouldOpenForegroundWindow = $true
        startsApplication = $false
    } | ConvertTo-Json -Depth 3
    return
}
$savedLocalAppData = [Environment]::GetEnvironmentVariable("LOCALAPPDATA", "Process")
$savedNamespace = [Environment]::GetEnvironmentVariable("AKUBROWSER_ISOLATED_TEST_CREDENTIAL_NAMESPACE", "Process")
$savedStartupDiagnostics = [Environment]::GetEnvironmentVariable("AKUBROWSER_CHROMIUM_STARTUP_DIAGNOSTICS", "Process")

try {
    New-Item -ItemType Directory -Force -Path $isolatedLocalAppData | Out-Null
    $env:LOCALAPPDATA = $isolatedLocalAppData
    $env:AKUBROWSER_ISOLATED_TEST_CREDENTIAL_NAMESPACE = $namespace
    [Environment]::SetEnvironmentVariable("AKUBROWSER_CHROMIUM_STARTUP_DIAGNOSTICS", $(if ($ChromiumStartupDiagnostics) { "1" } else { $null }), "Process")
    & $launcher --verify-only --install-root $tupleRoot
    if ($LASTEXITCODE -ne 0) { throw "The installed-app tuple failed launcher verification." }
    if ($DiagnosticPort -ne 0) {
        $pointer = Get-Content -Raw -LiteralPath (Join-Path $tupleRoot "runtime\current.json") | ConvertFrom-Json
        if ($pointer.version -notmatch '^\d+\.\d+\.\d+(?:[-.][A-Za-z0-9.-]+)?$') {
            throw "The test tuple has an invalid active version."
        }
        $runtime = Join-Path $tupleRoot ("runtime\versions\" + $pointer.version)
        $sidecar = Join-Path $runtime "AkuSidecar.exe"
        $config = Join-Path $runtime "config\sidecar.json"
        $chromium = Join-Path $runtime "chromium\bin\chrome.exe"
        $data = Join-Path $isolatedLocalAppData "AkuBrowser\data"
        $profile = Join-Path $isolatedLocalAppData "AkuBrowser\browser-profile"
        Write-Host "Opening isolated diagnostic app shell on port $DiagnosticPort without Bridge extension; this cannot validate Bridge readiness."
        & $sidecar --config $config --database (Join-Path $data "aku-sidecar.db") --port $DiagnosticPort --app-shell --chromium-path $chromium --browser-profile $profile
        if ($LASTEXITCODE -ne 0) { throw "The diagnostic Sidecar exited with code $LASTEXITCODE." }
        return
    }
    Write-Host "Opening the test tuple with isolated browser data and credential namespace. Close the app window to end this run."
    & $launcher --install-root $tupleRoot
    if ($LASTEXITCODE -ne 0) { throw "The installed-app test launcher exited with code $LASTEXITCODE." }
} finally {
    [Environment]::SetEnvironmentVariable("LOCALAPPDATA", $savedLocalAppData, "Process")
    [Environment]::SetEnvironmentVariable("AKUBROWSER_ISOLATED_TEST_CREDENTIAL_NAMESPACE", $savedNamespace, "Process")
    [Environment]::SetEnvironmentVariable("AKUBROWSER_CHROMIUM_STARTUP_DIAGNOSTICS", $savedStartupDiagnostics, "Process")
}
