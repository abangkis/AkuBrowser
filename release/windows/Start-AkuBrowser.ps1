[CmdletBinding()]
param(
    [string] $CodexPath = $env:AKU_CODEX_PATH,
    [ValidateRange(1, 65535)]
    [int] $Port = 47821,
    [string] $DataDirectory = "",
    [switch] $NoOpen
)

$ErrorActionPreference = "Stop"
$bundleRoot = $PSScriptRoot
$sidecarPath = Join-Path $bundleRoot "AkuSidecar.exe"
$configPath = Join-Path $bundleRoot "config\sidecar.json"
$releasePath = Join-Path $bundleRoot "release-manifest.json"

function Resolve-CodexPath([string] $RequestedPath) {
    $candidate = $RequestedPath
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        foreach ($name in @("codex.exe", "codex")) {
            $command = Get-Command $name -ErrorAction SilentlyContinue
            if ($null -ne $command) {
                return $command.Source
            }
        }
        throw "Codex App Server was not found. Install and sign in to Codex App, or rerun with -CodexPath <path-to-codex.exe>."
    }

    if ($candidate -notmatch '[\\/]') {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Codex executable was not found: $resolved"
    }
    return $resolved
}

function Open-Browser([string] $Url) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Url
    $startInfo.UseShellExecute = $true
    [void][Diagnostics.Process]::Start($startInfo)
}

function Open-WhenReady([string] $HealthUrl, [string] $BrowserUrl) {
    $script = @"
`$ErrorActionPreference = 'SilentlyContinue'
for (`$attempt = 0; `$attempt -lt 60; `$attempt++) {
    try {
        `$health = Invoke-RestMethod -Uri '$HealthUrl' -TimeoutSec 1
        if (`$health.status -eq 'ok') {
            `$startInfo = New-Object Diagnostics.ProcessStartInfo
            `$startInfo.FileName = '$BrowserUrl'
            `$startInfo.UseShellExecute = `$true
            [void][Diagnostics.Process]::Start(`$startInfo)
            exit 0
        }
    }
    catch {}
    Start-Sleep -Milliseconds 250
}
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-NoProfile -NonInteractive -EncodedCommand $encoded"
    $startInfo.UseShellExecute = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    [void][Diagnostics.Process]::Start($startInfo)
}

foreach ($required in @($sidecarPath, $configPath, $releasePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "AkuBrowser bundle is incomplete: $required"
    }
}

$release = Get-Content -LiteralPath $releasePath -Raw | ConvertFrom-Json
$browserUrl = "http://127.0.0.1:$Port"
$healthUrl = "$browserUrl/api/health"

try {
    $active = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    if ($active.status -eq "ok" -and $active.version -eq $release.version) {
        Write-Host "AkuBrowser $($release.version) is already running at $browserUrl"
        if (-not $NoOpen) { Open-Browser $browserUrl }
        exit 0
    }
    throw "Port $Port is already owned by a different AkuSidecar version or service."
}
catch {
    if ($_.Exception.Message -like "Port $Port is already owned*") { throw }
}

$resolvedCodex = Resolve-CodexPath $CodexPath
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $localData = [Environment]::GetFolderPath("LocalApplicationData")
    if ([string]::IsNullOrWhiteSpace($localData)) {
        $DataDirectory = Join-Path $bundleRoot "data"
    }
    else {
        $DataDirectory = Join-Path $localData "AkuBrowser\data"
    }
}
$DataDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataDirectory)
New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
$databasePath = Join-Path $DataDirectory "aku-sidecar.db"

Write-Host "Starting AkuBrowser $($release.version)"
Write-Host "UI: $browserUrl"
Write-Host "Data: $databasePath"
Write-Host "Press Ctrl+C to stop AkuBrowser."

if (-not $NoOpen) {
    Open-WhenReady $healthUrl $browserUrl
}

& $sidecarPath `
    --config $configPath `
    --codex-path $resolvedCodex `
    --database $databasePath `
    --port $Port
exit $LASTEXITCODE
