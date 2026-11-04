[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$browserRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'source-cache.ps1')

function Assert-Equal([object]$Actual, [object]$Expected, [string]$Label) {
    if ($Actual -ne $Expected) { throw "$Label expected '$Expected' but got '$Actual'." }
}
function Assert-True([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw $Label }
}
function Set-ProcessEnvironment([string]$Name, [AllowNull()][string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

$environmentNames = @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'npm_config_cache', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE', 'TEMP', 'TMP', 'CACHE_CAPTURE')
$originalEnvironment = @{}
foreach ($name in $environmentNames) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$fixtureBase = [IO.Path]::GetFullPath((Join-Path $browserRoot '.cache/source-build-cache-tests'))
$fixtureRoot = Join-Path $fixtureBase ('powershell-' + [Guid]::NewGuid().ToString('N'))

try {
    $ancestor = Join-Path $fixtureRoot 'ancestor'
    $repository = Join-Path $ancestor 'project/repo'
    $sharedTemp = Join-Path $ancestor 'SharedTemp'
    [IO.Directory]::CreateDirectory($sharedTemp) | Out-Null
    [IO.Directory]::CreateDirectory($repository) | Out-Null

    foreach ($name in @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'npm_config_cache')) { Set-ProcessEnvironment $name $null }
    $defaultPaths = Get-SourceBuildCachePaths -Repository $repository
    $cacheRoot = Join-Path $sharedTemp 'build-cache'
    Assert-Equal $defaultPaths.GoBuild (Join-Path $cacheRoot 'go-build') 'default Go build cache'
    Assert-Equal $defaultPaths.GoModules (Join-Path $cacheRoot 'go-mod') 'default Go module cache'
    Assert-Equal $defaultPaths.Npm (Join-Path $cacheRoot 'npm') 'default npm cache'

    $configuredRoot = Join-Path $fixtureRoot 'configured-cache'
    $configDirectory = Join-Path $repository '.cache'
    [IO.Directory]::CreateDirectory($configDirectory) | Out-Null
    $configPath = Join-Path $configDirectory 'source-build-cache.json'
    [IO.File]::WriteAllText($configPath, (@{ schemaVersion = 1; root = $configuredRoot } | ConvertTo-Json -Compress))
    $configured = Get-SourceBuildCachePaths -Repository $repository
    Assert-Equal $configured.GoBuild (Join-Path $configuredRoot 'go-build') 'configured Go build cache'
    Assert-Equal $configured.GoModules (Join-Path $configuredRoot 'go-mod') 'configured Go module cache'
    Assert-Equal $configured.Npm (Join-Path $configuredRoot 'npm') 'configured npm cache'

    $overrideBuild = Join-Path $fixtureRoot 'override-build'
    $overrideModules = Join-Path $fixtureRoot 'override-modules'
    $overrideNpm = Join-Path $fixtureRoot 'override-npm'
    Set-ProcessEnvironment 'GOCACHE' $overrideBuild
    Set-ProcessEnvironment 'GOMODCACHE' $overrideModules
    Set-ProcessEnvironment 'npm_config_cache' $overrideNpm
    $overridden = Get-SourceBuildCachePaths -Repository $repository
    Assert-Equal $overridden.GoBuild $overrideBuild 'incoming GOCACHE override'
    Assert-Equal $overridden.GoModules $overrideModules 'incoming GOMODCACHE override'
    Assert-Equal $overridden.Npm $overrideNpm 'incoming npm cache override'

    foreach ($name in @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'npm_config_cache')) { Set-ProcessEnvironment $name $null }
    $expectedRestoredEnvironment = @{}
    foreach ($name in @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'npm_config_cache')) { $expectedRestoredEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    Set-ProcessEnvironment 'GIT_TERMINAL_PROMPT' '1'
    Set-ProcessEnvironment 'GCM_INTERACTIVE' '1'
    $stubRoot = Join-Path $fixtureRoot 'compiler-stubs'
    [IO.Directory]::CreateDirectory($stubRoot) | Out-Null
    $fakeGo = Join-Path $stubRoot 'go.ps1'
    $fakeNpm = Join-Path $stubRoot 'npm.ps1'
    $goStubContent = '[ordered]@{ GOCACHE = $env:GOCACHE; GOMODCACHE = $env:GOMODCACHE; GOTMPDIR = $env:GOTMPDIR; GitPrompt = $env:GIT_TERMINAL_PROMPT; CredentialPrompt = $env:GCM_INTERACTIVE; Temp = $env:TEMP; Tmp = $env:TMP } | ConvertTo-Json -Compress | Set-Content -LiteralPath $env:CACHE_CAPTURE'
    $npmStubContent = '[ordered]@{ NpmCache = $env:npm_config_cache } | ConvertTo-Json -Compress | Set-Content -LiteralPath $env:CACHE_CAPTURE'
    [IO.File]::WriteAllText($fakeGo, $goStubContent, (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($fakeNpm, $npmStubContent, (New-Object System.Text.UTF8Encoding($false)))
    $failureContext = $null
    $failureTemp = $null
    try {
        $failureContext = Enter-SourceBuildEnvironment -Repository $repository -RunName 'failure-fixture'
        $failureTemp = $failureContext.TempDirectory
        Assert-Equal $env:GOCACHE (Join-Path $configuredRoot 'go-build') 'entered Go build cache'
        Assert-Equal $env:GOMODCACHE (Join-Path $configuredRoot 'go-mod') 'entered Go module cache'
        Assert-Equal $env:npm_config_cache (Join-Path $configuredRoot 'npm') 'entered npm cache'
        Assert-Equal $env:GIT_TERMINAL_PROMPT '0' 'noninteractive Git prompt'
        Assert-Equal $env:GCM_INTERACTIVE '0' 'noninteractive credential manager'
        $env:CACHE_CAPTURE = Join-Path $fixtureRoot 'go-stub.json'
        & $fakeGo
        $goEvidence = Get-Content -LiteralPath $env:CACHE_CAPTURE -Raw | ConvertFrom-Json
        Assert-Equal $goEvidence.GOCACHE $env:GOCACHE 'compiler stub shared cache'
        Assert-Equal $goEvidence.GOMODCACHE $env:GOMODCACHE 'compiler stub module cache'
        Assert-Equal $goEvidence.GOTMPDIR $failureTemp 'compiler stub per-run temp'
        Assert-Equal $goEvidence.Temp $failureTemp 'compiler stub TEMP'
        Assert-Equal $goEvidence.Tmp $failureTemp 'compiler stub TMP'
        Assert-Equal $goEvidence.GitPrompt '0' 'compiler stub Git prompt suppression'
        Assert-Equal $goEvidence.CredentialPrompt '0' 'compiler stub credential prompt suppression'
        $env:CACHE_CAPTURE = Join-Path $fixtureRoot 'npm-stub.json'
        & $fakeNpm
        $npmEvidence = Get-Content -LiteralPath $env:CACHE_CAPTURE -Raw | ConvertFrom-Json
        Assert-Equal $npmEvidence.NpmCache $env:npm_config_cache 'package-manager stub cache'
        Assert-True ($failureTemp.StartsWith((Join-Path $repository '.cache/source-build-temp'), [StringComparison]::OrdinalIgnoreCase)) 'Go temp must remain project local.'
        Assert-True (Test-Path -LiteralPath $failureTemp -PathType Container) 'per-run Go temp must exist during execution.'
        throw 'injected cache fixture failure'
    }
    catch {
        if ($_.Exception.Message -ne 'injected cache fixture failure') { throw }
    }
    finally {
        if ($null -ne $failureContext) { Exit-SourceBuildEnvironment -Context $failureContext }
    }
    Assert-True (-not (Test-Path -LiteralPath $failureTemp)) 'owned per-run Go temp must be removed after failure.'
    foreach ($name in @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'npm_config_cache')) {
        $actualValue = [Environment]::GetEnvironmentVariable($name, 'Process')
        $expectedValue = $expectedRestoredEnvironment[$name]
        if ($null -eq $expectedValue) { Assert-True ($null -eq $actualValue) "environment restore failed for $name." }
        else { Assert-Equal $actualValue $expectedValue "environment restore for $name" }
    }
    Assert-Equal $env:GIT_TERMINAL_PROMPT '1' 'Git prompt restoration'
    Assert-Equal $env:GCM_INTERACTIVE '1' 'credential manager restoration'
    $secondContext = Enter-SourceBuildEnvironment -Repository $repository -RunName 'unique-fixture'
    try { Assert-True ($secondContext.TempDirectory -ne $failureTemp) 'each run must receive a unique Go temp directory.' }
    finally { Exit-SourceBuildEnvironment -Context $secondContext }

    $customTemp = Join-Path $fixtureRoot 'incoming-gotmpdir'
    Set-ProcessEnvironment 'GOTMPDIR' $customTemp
    $incomingContext = Enter-SourceBuildEnvironment -Repository $repository -RunName 'incoming-temp-fixture'
    try {
        Assert-Equal $incomingContext.TempDirectory $customTemp 'incoming GOTMPDIR override'
        Assert-Equal $env:TEMP $customTemp 'incoming TEMP override'
        Assert-Equal $env:TMP $customTemp 'incoming TMP override'
        Assert-True (-not $incomingContext.OwnsTempDirectory) 'incoming GOTMPDIR must remain caller-owned.'
    }
    finally { Exit-SourceBuildEnvironment -Context $incomingContext }
    Assert-True (Test-Path -LiteralPath $customTemp -PathType Container) 'caller-owned GOTMPDIR must not be deleted.'

    $ownedTempRoot = [IO.Path]::GetFullPath((Join-Path $repository '.cache/source-build-temp'))
    $outsideTemp = Join-Path ($ownedTempRoot + '-outside') ('outside-fixture-{0}-{1}' -f $PID, [Guid]::NewGuid().ToString('N'))
    $ownedTempPrefix = $ownedTempRoot + [IO.Path]::DirectorySeparatorChar
    Assert-True (-not $outsideTemp.StartsWith($ownedTempPrefix, [StringComparison]::OrdinalIgnoreCase)) 'the regression directory must remain outside the owned temp root.'
    Assert-True ([IO.Path]::GetFileName($outsideTemp) -match '^[A-Za-z0-9_-]+-[0-9]+-[0-9a-f]{32}$') 'the regression directory must satisfy the generated-name guard.'
    [IO.Directory]::CreateDirectory($outsideTemp) | Out-Null
    $outsideEvidence = Join-Path $outsideTemp 'preserve.txt'
    [IO.File]::WriteAllText($outsideEvidence, 'preserve this out-of-root directory')
    $outsideContext = [pscustomobject]@{
        Repository = $repository
        TempDirectory = $outsideTemp
        OwnsTempDirectory = $true
        SavedEnvironment = @{}
    }
    Exit-SourceBuildEnvironment -Context $outsideContext
    Assert-True (Test-Path -LiteralPath $outsideTemp -PathType Container) 'cleanup must preserve an out-of-root directory even when ownership is asserted.'
    Assert-Equal ([IO.File]::ReadAllText($outsideEvidence)) 'preserve this out-of-root directory' 'out-of-root sentinel contents'

    $wrapperNames = @('check.ps1', 'test-windows-runtime-updater.ps1', 'build-windows-preview.ps1', 'build-windows-runtime-installer.ps1', 'build-windows-installed-app.ps1')
    foreach ($name in $wrapperNames) {
        $path = Join-Path $PSScriptRoot $name
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-True ($parseErrors.Count -eq 0) "PowerShell parse errors found in $name."
        $source = Get-Content -LiteralPath $path -Raw
        Assert-True ($source.Contains('Enter-SourceBuildEnvironment') -and $source.Contains('Exit-SourceBuildEnvironment')) "cache setup or restoration missing in $name."
        Assert-True (-not $source.Contains('.go-cache')) "legacy per-workspace cache path remains in $name."
    }
    Assert-True ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-windows-preview.ps1') -Raw).Contains('Complete-AkuOutput -Id $outputOwner -Failed')) 'preview output lifecycle failure guard changed.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-windows-runtime-installer.ps1') -Raw).Contains('Complete-AkuOutput -Id $outputOwner -Failed')) 'runtime installer output lifecycle failure guard changed.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-windows-installed-app.ps1') -Raw).Contains('Reset-ArtifactPath $artifactRoot $OutputRoot')) 'installed-app output path guard changed.'

    Write-Output 'source build cache PowerShell fixtures: passed'
}
finally {
    foreach ($name in $environmentNames) { Set-ProcessEnvironment $name $originalEnvironment[$name] }
    $base = [IO.Path]::GetFullPath($fixtureBase).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath($fixtureRoot)
    if ($target.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $target -PathType Container)) {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    }
}
