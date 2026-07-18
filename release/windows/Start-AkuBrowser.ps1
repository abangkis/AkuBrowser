[CmdletBinding()]
param(
    [string] $CodexPath = $env:AKU_CODEX_PATH,
    [ValidateRange(1, 65535)]
    [int] $Port = 11122,
    [string] $DataDirectory = "",
    [switch] $NoOpen,
    [switch] $DiagnoseCodex
)

$ErrorActionPreference = "Stop"
$bundleRoot = $PSScriptRoot
$sidecarPath = Join-Path $bundleRoot "AkuSidecar.exe"
$configPath = Join-Path $bundleRoot "config\sidecar.json"
$releasePath = Join-Path $bundleRoot "release-manifest.json"

function Resolve-CodexRuntime([string] $RequestedPath) {
    $probeArguments = @("--discover-codex")
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $probeArguments += @("--codex-path", $RequestedPath)
    }

    $probeText = (& $sidecarPath @probeArguments | Out-String).Trim()
    $probeExit = $LASTEXITCODE
    try {
        $probe = $probeText | ConvertFrom-Json
    }
    catch {
        Write-Host "AkuBrowser could not read the Codex runtime diagnostic." -ForegroundColor Red
        Write-Host "Run: .\Start-AkuBrowser.ps1 -DiagnoseCodex"
        return $null
    }

    if ($probeExit -ne 0 -or $probe.status -ne "ok") {
        Write-Host $probe.message -ForegroundColor Red
        if ($null -ne $probe.attempts) {
            Write-Host "Locations checked:"
            foreach ($attempt in $probe.attempts | Select-Object -First 12) {
                $label = if ([string]::IsNullOrWhiteSpace($attempt.path)) { $attempt.source } else { $attempt.path }
                Write-Host "  - $label [$($attempt.source)]: $($attempt.reason)"
            }
        }
        Write-Host "Install and sign in to Codex App, or install Codex CLI with App Server support."
        Write-Host "Then retry, set AKU_CODEX_PATH, or use -CodexPath <path-to-codex>."
        Write-Host "Codex setup: https://help.openai.com/en/articles/11096431"
        return $null
    }
    return $probe
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

$codexRuntime = Resolve-CodexRuntime $CodexPath
if ($null -eq $codexRuntime) { exit 2 }
Write-Host "Codex runtime: $($codexRuntime.version)"
Write-Host "Discovered from: $($codexRuntime.source)"
Write-Host "Executable: $($codexRuntime.executable)"
if ($DiagnoseCodex) { exit 0 }

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
    --codex-path $($codexRuntime.executable) `
    --database $databasePath `
    --port $Port
exit $LASTEXITCODE
