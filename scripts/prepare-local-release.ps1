[CmdletBinding()]
param(
    [string] $OutputRoot = "",
    [string] $C2paToolPath = "",
    [ValidateSet('user', 'codex')]
    [string] $Actor = 'codex',
    [ValidateRange(0, 3600)]
    [int] $WaitForIdleSeconds = 900,
    [switch] $SkipValidation,
    [switch] $AllowDirty,
    [switch] $SkipDevelopmentSync,
    [switch] $SkipBridgeReload
)

$ErrorActionPreference = 'Stop'
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$sidecarRoot = Join-Path $workspaceRoot 'AkuSidecar'
$release = Get-Content -LiteralPath (Join-Path $browserRoot 'release\release-manifest.json') -Raw | ConvertFrom-Json

function Invoke-RepositoryScript([string] $Path, [hashtable] $Parameters) {
    & $Path @Parameters
    if ($LASTEXITCODE -ne 0) {
        throw "Script failed with exit code $LASTEXITCODE`: $Path"
    }
}

function Get-BridgeHealth {
    try {
        return Invoke-RestMethod -Uri 'http://127.0.0.1:11122/api/bridge/health' -TimeoutSec 3
    }
    catch {
        return $null
    }
}

function Test-BridgeMatchesRelease($Status) {
    if ($null -eq $Status -or -not $Status.bridge.compatible) {
        return $false
    }
    $actual = $Status.bridge.actual
    $expected = $release.components.akuBridge
    $expectedBuildId = "aku-bridge-$($expected.version)-$($expected.runtimeRevision)"
    return [string]$actual.extensionVersion -eq [string]$expected.version `
        -and [string]$actual.runtimeRevision -eq [string]$expected.runtimeRevision `
        -and [string]$actual.buildId -eq $expectedBuildId `
        -and [string]$actual.contractVersion -eq [string]$expected.contractVersion
}

function Wait-ReleaseBridge([int] $TimeoutSeconds = 15) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $status = Get-BridgeHealth
        if (Test-BridgeMatchesRelease $status) {
            return $status
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    return $status
}

function Invoke-CooperativeBridgeReload([int] $TimeoutSeconds = 45) {
    # A Sidecar replacement rotates the process epoch and Bridge token. Give
    # the already-installed extension a bounded chance to re-bootstrap and
    # publish its normal heartbeat before asking it to reload itself.
    $status = Wait-ReleaseBridge
    if (Test-BridgeMatchesRelease $status) {
        Write-Host '[release] AkuBridge already matches the rebuilt development runtime.' -ForegroundColor Green
        return $status.bridge
    }

    $bootstrap = Invoke-RestMethod -Uri 'http://127.0.0.1:11122/api/bootstrap' -TimeoutSec 5
    if ([string]::IsNullOrWhiteSpace([string]$bootstrap.bridgeToken)) {
        throw 'AkuSidecar bootstrap did not provide the bounded Bridge token.'
    }
    $headers = @{
        'X-Aku-Bridge-Token' = [string]$bootstrap.bridgeToken
        'X-Aku-Bridge-Contract' = [string]$bootstrap.bridgeContractVersion
    }
    $requestId = 'local_release_' + [Guid]::NewGuid().ToString('n')
    $body = @{
        requestId = $requestId
        actor = @{ actorType = 'agent'; actorId = 'local-release-reconciler' }
        reason = "reconcile unpacked AkuBridge with local release $($release.version)"
    } | ConvertTo-Json -Depth 5
    $requested = Invoke-RestMethod `
        -Uri 'http://127.0.0.1:11122/api/operations/bridge/actions/reload-self' `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 5
    $actionId = [string]$requested.action.id
    if ([string]::IsNullOrWhiteSpace($actionId)) {
        throw 'AkuSidecar did not return a cooperative Bridge reload action ID.'
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $action = Invoke-RestMethod `
            -Uri "http://127.0.0.1:11122/api/operations/bridge/actions/$actionId" `
            -Headers $headers `
            -TimeoutSec 3
        if ($action.action.status -eq 'completed') {
            $health = Get-BridgeHealth
            if (-not (Test-BridgeMatchesRelease $health)) {
                throw 'AkuBridge reload completed without the exact development release heartbeat.'
            }
            Write-Host '[release] AkuBridge cooperative reload completed.' -ForegroundColor Green
            return $health.bridge
        }
        if ($action.action.status -eq 'failed') {
            $recovered = Wait-ReleaseBridge -TimeoutSeconds 3
            if (Test-BridgeMatchesRelease $recovered) {
                Write-Host '[release] AkuBridge recovered through its normal heartbeat while reload was pending.' -ForegroundColor Green
                return $recovered.bridge
            }
            throw "AkuBridge cooperative reload failed: $($action.action.errorCategory) - $($action.action.message)"
        }
    }
    throw "AkuBridge cooperative reload did not complete within $TimeoutSeconds seconds. Keep an AkuBrowser page open so its relay can accept reload_self."
}

$buildParameters = @{}
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $buildParameters.OutputRoot = $OutputRoot }
if ([string]::IsNullOrWhiteSpace($C2paToolPath)) {
    $C2paToolPath = (& (Join-Path $PSScriptRoot 'provision-shared-c2patool.ps1') | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($C2paToolPath)) {
        throw 'The shared c2patool could not be provisioned.'
    }
}
$buildParameters.C2paToolPath = $C2paToolPath
if ($SkipValidation) { $buildParameters.SkipValidation = $true }
if ($AllowDirty) { $buildParameters.AllowDirty = $true }

Write-Host "[release] Building and validating AkuBrowser $($release.version)..." -ForegroundColor Cyan
Invoke-RepositoryScript (Join-Path $PSScriptRoot 'build-windows-preview.ps1') $buildParameters

$effectiveOutputRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    Join-Path $browserRoot 'artifacts'
} else {
    [IO.Path]::GetFullPath($OutputRoot)
}
$zipPath = Join-Path $effectiveOutputRoot "AkuBrowser-$($release.version)-windows-x64.zip"
Invoke-RepositoryScript (Join-Path $PSScriptRoot 'test-windows-preview.ps1') @{ ZipPath = $zipPath }

if (-not $SkipDevelopmentSync) {
    Write-Host '[release] Reconciling the generated AkuSidecar development runtime...' -ForegroundColor Cyan
    Invoke-RepositoryScript (Join-Path $sidecarRoot 'scripts\restart-dev.ps1') @{
        Actor = $Actor
        WaitForIdleSeconds = $WaitForIdleSeconds
    }
    if (-not $SkipBridgeReload) {
        $null = Invoke-CooperativeBridgeReload
    }
}

$health = Invoke-RestMethod -Uri 'http://127.0.0.1:11122/api/health' -TimeoutSec 3
$bridge = Get-BridgeHealth
$runtimeStatePath = Join-Path $sidecarRoot 'runtime\dev\aku-sidecar.exe.runtime-state.json'
$runtimeState = if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) {
    Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
} else {
    $null
}

[ordered]@{
    status = if (
        $health.version -eq $release.components.akuSidecar.version -and
        $null -ne $bridge -and
        $bridge.bridge.compatible
    ) { 'ok' } else { 'attention' }
    release = $release.version
    bundle = $zipPath
    developmentRuntime = [ordered]@{
        version = $health.version
        sourceCommit = $runtimeState.sourceCommit
        binarySha256 = $runtimeState.binarySha256
        builtAtUtc = $runtimeState.builtAtUtc
    }
    akuBridge = [ordered]@{
        version = $bridge.bridge.actual.extensionVersion
        compatible = [bool]$bridge.bridge.compatible
        runtimeRevision = $bridge.bridge.actual.runtimeRevision
    }
} | ConvertTo-Json -Depth 6
