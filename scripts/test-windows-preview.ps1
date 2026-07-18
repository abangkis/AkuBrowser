[CmdletBinding()]
param(
    [string] $ArtifactDirectory = "",
    [string] $ZipPath = ""
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$release = Get-Content -LiteralPath (Join-Path $browserRoot "release\release-manifest.json") -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
    if ([string]::IsNullOrWhiteSpace($ZipPath)) {
        $ZipPath = Join-Path $browserRoot "artifacts\AkuBrowser-$($release.version)-windows-x64.zip"
    }
    $ZipPath = [IO.Path]::GetFullPath($ZipPath)
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Preview ZIP was not found: $ZipPath"
    }
    $extractionRoot = Join-Path ([IO.Path]::GetTempPath()) ("akubrowser-release-extract-" + [Guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Force -Path $extractionRoot | Out-Null
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractionRoot
        & $PSCommandPath -ArtifactDirectory $extractionRoot
    }
    finally {
        $absoluteExtraction = [IO.Path]::GetFullPath($extractionRoot)
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if ($absoluteExtraction.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $absoluteExtraction)) {
            Remove-Item -LiteralPath $absoluteExtraction -Recurse -Force
        }
    }
    exit 0
}
$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function ConvertTo-NativeArgument([string] $Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

foreach ($required in @(
    "AkuSidecar.exe",
    "AkuBridge\manifest.json",
    "config\sidecar.json",
    "release-manifest.json",
    "artifact-manifest.json",
    "checksums.sha256",
    "Start-AkuBrowser.ps1",
    "Start-AkuBrowser.cmd",
    "README.md"
)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $ArtifactDirectory $required) -PathType Leaf) "Artifact is missing $required"
}

$checksumLines = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "checksums.sha256")
foreach ($line in $checksumLines) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
        throw "Invalid checksum line: $line"
    }
    $expected = $Matches[1]
    $relative = $Matches[2].Replace("/", [IO.Path]::DirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $ArtifactDirectory $relative))
    $prefix = $ArtifactDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Assert-True ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Checksum path escapes the artifact: $relative"
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Checksummed file is missing: $relative"
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-True ($actual -eq $expected) "Checksum mismatch: $relative"
}

$artifactRelease = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "release-manifest.json") -Raw | ConvertFrom-Json
$bridgeManifest = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "AkuBridge\manifest.json") -Raw | ConvertFrom-Json
Assert-True ($artifactRelease.version -eq $release.version) "Artifact release version differs from AkuBrowser."
Assert-True ($bridgeManifest.version_name -eq $release.components.akuBridge.version) "Bundled AkuBridge product version differs from the release tuple."
Assert-True ($bridgeManifest.version -eq $release.components.akuBridge.chromeVersion) "Bundled AkuBridge Chrome version differs from the release tuple."

$savedPath = $env:PATH
try {
    $env:PATH = "$env:SystemRoot\System32"
    $codexProbeText = & (Join-Path $ArtifactDirectory "AkuSidecar.exe") --discover-codex
    $codexProbeExit = $LASTEXITCODE
}
finally {
    $env:PATH = $savedPath
}
$codexProbe = ($codexProbeText | Out-String) | ConvertFrom-Json
Assert-True ($codexProbeExit -eq 0) "Packaged AkuSidecar could not discover Codex with PATH restricted."
Assert-True ($codexProbe.status -eq "ok") "Packaged Codex discovery did not return an ok status."
Assert-True (-not [string]::IsNullOrWhiteSpace($codexProbe.executable)) "Packaged Codex discovery returned no executable."
Assert-True (-not [string]::IsNullOrWhiteSpace($codexProbe.version)) "Packaged Codex discovery returned no version."

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ("akubrowser-release-smoke-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
$database = Join-Path $smokeRoot "aku-sidecar.db"
$process = $null
try {
    $arguments = @(
        "--config", (Join-Path $ArtifactDirectory "config\sidecar.json"),
        "--provider", "deterministic",
        "--database", $database,
        "--port", [string]$port
    ) | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $ArtifactDirectory "AkuSidecar.exe"
    $startInfo.Arguments = $arguments -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    Assert-True $process.Start() "Packaged AkuSidecar process could not be started."

    $health = $null
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        if ($process.HasExited) {
            $errorText = $process.StandardError.ReadToEnd()
            throw "Packaged AkuSidecar exited during startup: $errorText"
        }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/health" -TimeoutSec 1
            if ($health.status -eq "ok") { break }
        }
        catch {}
        Start-Sleep -Milliseconds 125
    }
    Assert-True ($null -ne $health -and $health.status -eq "ok") "Packaged AkuSidecar did not become healthy."
    Assert-True ($health.version -eq $release.components.akuSidecar.version) "Packaged AkuSidecar reports the wrong version."
    Assert-True ($health.runtime -eq "go") "Packaged AkuSidecar does not report the Go runtime."

    $bootstrap = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/bootstrap" -TimeoutSec 5
    Assert-True ($bootstrap.settings.loadProfile -eq "standard") "Packaged fresh database does not use Standard 1x."
    Assert-True ($bootstrap.settings.aiDetectionPresentation -eq "drawer") "Packaged fresh database does not default AI Signals to Drawer."
    Assert-True ($bootstrap.settings.reasoningEvaluationProfile -eq "luna_xhigh") "Packaged fresh database does not default evaluation to Luna XHigh."

    $ui = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/" -TimeoutSec 5
    Assert-True ($ui.StatusCode -eq 200 -and $ui.Content -match "AkuBrowser") "Embedded AkuBrowser UI was not delivered."

    [ordered]@{
        status = "ok"
        version = $health.version
        runtime = $health.runtime
        provider = $health.provider
        port = $port
        checksumFiles = @($checksumLines).Count
        defaultLoadProfile = $bootstrap.settings.loadProfile
        defaultAIPresentation = $bootstrap.settings.aiDetectionPresentation
        defaultEvaluationProfile = $bootstrap.settings.reasoningEvaluationProfile
        codexDiscoverySource = $codexProbe.source
        codexVersion = $codexProbe.version
    } | ConvertTo-Json
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
    }
    $absoluteSmoke = [IO.Path]::GetFullPath($smokeRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($absoluteSmoke.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $absoluteSmoke)) {
        Remove-Item -LiteralPath $absoluteSmoke -Recurse -Force
    }
}
