#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $TupleDirectory,
    [Parameter(Mandatory = $true)] [string] $AcceptanceRoot,
    [string] $BrowserRoot = (Split-Path -Parent $PSScriptRoot),
    [switch] $PlanOnly,
    [switch] $AllowForeground,
    [ValidateRange(1, 65535)] [int] $DiagnosticPort = 0,
    [switch] $ChromiumStartupDiagnostics
)

$ErrorActionPreference = "Stop"
if (-not $PlanOnly -and -not $AllowForeground) {
    throw "This acceptance run opens pinned Chromium in the foreground. Pass -AllowForeground only after the user approves the visual test."
}

$browserRoot = [IO.Path]::GetFullPath($BrowserRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$buildRoot = [IO.Path]::GetFullPath((Join-Path $browserRoot "build")).TrimEnd([IO.Path]::DirectorySeparatorChar)
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $browserRoot "artifacts")).TrimEnd([IO.Path]::DirectorySeparatorChar)
$stateRoot = [IO.Path]::GetFullPath((Join-Path $browserRoot "acceptance-state")).TrimEnd([IO.Path]::DirectorySeparatorChar)
$legacyBuildRoot = Join-Path $stateRoot "legacy-build"
$legacyArtifactsRoot = Join-Path $stateRoot "legacy-artifacts"
$acceptanceRoot = [IO.Path]::GetFullPath($AcceptanceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$tupleRoot = [IO.Path]::GetFullPath($TupleDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)

function Assert-NoReparseAncestors([string] $Path, [string] $Description) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPath = [IO.Path]::GetPathRoot($fullPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $cursor = $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            Assert-NoReparseAttributes $item.Attributes "$Description or one of its ancestors"
        }
        if ($cursor.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $next = $parent.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        if ($next.Equals($cursor, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $next
    }
}

function Assert-NoReparseAttributes([IO.FileAttributes] $Attributes, [string] $Description) {
    if (($Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must not be a reparse point."
    }
}

function Test-PathWithin([string] $Path, [string] $Root) {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

Assert-NoReparseAncestors $browserRoot "BrowserRoot"
Assert-NoReparseAncestors $buildRoot "AkuBrowser/build"
Assert-NoReparseAncestors $artifactsRoot "AkuBrowser/artifacts"
Assert-NoReparseAncestors $stateRoot "AkuBrowser/acceptance-state"
Assert-NoReparseAncestors $acceptanceRoot "AcceptanceRoot"
Assert-NoReparseAncestors $tupleRoot "TupleDirectory"
if (-not (Test-Path -LiteralPath $browserRoot -PathType Container)) {
    throw "BrowserRoot must be an existing directory."
}
foreach ($managedRoot in @($buildRoot, $artifactsRoot, $stateRoot, $legacyBuildRoot, $legacyArtifactsRoot, $acceptanceRoot)) {
    if ((Test-Path -LiteralPath $managedRoot) -and -not (Test-Path -LiteralPath $managedRoot -PathType Container)) {
        throw "A required acceptance path exists but is not a directory: $managedRoot"
    }
}

$acceptanceParent = [IO.Path]::GetDirectoryName($acceptanceRoot)
if (-not $acceptanceParent.Equals($stateRoot, [StringComparison]::OrdinalIgnoreCase) -and
    -not $acceptanceParent.Equals($legacyBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "AcceptanceRoot must be a direct child of AkuBrowser/acceptance-state or acceptance-state/legacy-build."
}
if ($acceptanceParent.Equals($legacyBuildRoot, [StringComparison]::OrdinalIgnoreCase) -and
    -not (Test-Path -LiteralPath $acceptanceRoot -PathType Container)) {
    throw "A legacy AcceptanceRoot must already exist as a directory."
}
$tupleAllowed = @($buildRoot, $artifactsRoot, $legacyBuildRoot, $legacyArtifactsRoot) | Where-Object { Test-PathWithin $tupleRoot $_ }
if ($tupleAllowed.Count -eq 0) {
    throw "TupleDirectory must be under AkuBrowser/build, AkuBrowser/artifacts, acceptance-state/legacy-build, or acceptance-state/legacy-artifacts."
}
if ($tupleRoot.Equals($acceptanceRoot, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-PathWithin $tupleRoot $acceptanceRoot) -or
    (Test-PathWithin $acceptanceRoot $tupleRoot)) {
    throw "AcceptanceRoot and TupleDirectory must be separate directories."
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
if ((Test-PathWithin $isolatedLocalAppData $realLocalAppData) -or
    (Test-PathWithin $realLocalAppData $isolatedLocalAppData)) {
    throw "The isolated LOCALAPPDATA path overlaps the real user profile."
}
Assert-NoReparseAncestors $isolatedLocalAppData "Isolated LOCALAPPDATA"

function Get-CredentialNamespace([string] $Path) {
    $digest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))
    return "AkuBrowserTest-" + [Convert]::ToHexString($digest).Substring(0, 16).ToLowerInvariant()
}

$namespace = Get-CredentialNamespace $acceptanceRoot
if ([IO.Path]::GetDirectoryName($acceptanceRoot).Equals($legacyBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $receiptRoot = Join-Path $stateRoot "migration-receipts"
    if (-not (Test-Path -LiteralPath $receiptRoot -PathType Container)) {
        throw "A legacy acceptance root requires its migration receipt to preserve the credential namespace."
    }
    Assert-NoReparseAncestors $receiptRoot "Migration receipt directory"
    $receiptDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($acceptanceRoot.ToLowerInvariant()))).ToLowerInvariant()
    $receiptPath = Join-Path $receiptRoot ("build-" + $receiptDigest + ".json")
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "A legacy acceptance root has no completed migration receipt; refusing to change its credential namespace."
    }
    $receiptFile = Get-Item -LiteralPath $receiptPath -Force
    Assert-NoReparseAttributes $receiptFile.Attributes "Migration receipt"
    try { $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json } catch {
        throw "A legacy acceptance root has an invalid migration receipt; refusing to change its credential namespace."
    }
    if ([int]$receipt.schemaVersion -ne 1 -or [string]$receipt.status -ne "moved" -or
        [string]$receipt.outputClass -ne "build" -or -not [bool]$receipt.isAcceptanceRoot -or
        [string]$receipt.destinationPath -ne $acceptanceRoot -or
        [string]::IsNullOrWhiteSpace([string]$receipt.originalPath) -or
        -not ([IO.Path]::GetDirectoryName([string]$receipt.originalPath)).Equals($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$receipt.originalCredentialNamespace -ne (Get-CredentialNamespace ([string]$receipt.originalPath))) {
        throw "A legacy acceptance root has an invalid migration receipt; refusing to change its credential namespace."
    }
    $namespace = [string]$receipt.originalCredentialNamespace
}
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
