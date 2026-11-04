[CmdletBinding()]
param(
    [switch] $FixtureChild,
    [string] $FixtureRoot,
    [switch] $CallerTemp
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$PSStyle.OutputRendering = 'PlainText'
$browserRoot = Split-Path -Parent $PSScriptRoot
$fixtureBase = [IO.Path]::GetFullPath((Join-Path $browserRoot '.cache/source-build-cache-tests'))
$environmentNames = @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'npm_config_cache', 'TEMP', 'TMP', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Equal([object] $Actual, [object] $Expected, [string] $Message) {
    if ($Actual -cne $Expected) { throw "$Message expected '$Expected', got '$Actual'." }
}

function Get-FixtureEnvironment {
    $values = @{}
    foreach ($name in $environmentNames) { $values[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    return $values
}

function Assert-OwnedFixture([string] $Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = $fixtureBase.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Assert-True ($absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) 'fixture must stay inside the owned test root'
    return $absolute
}

if ($FixtureChild) {
    $FixtureRoot = Assert-OwnedFixture $FixtureRoot
    $project = Join-Path $FixtureRoot 'AkuBrowser'
    $configuredCache = Join-Path $FixtureRoot 'configured-cache'
    $overrideCache = Join-Path $FixtureRoot 'override-cache'
    $callerGo = Join-Path $FixtureRoot 'caller-go'
    $output = Join-Path $FixtureRoot 'output'
    foreach ($name in @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'npm_config_cache')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    if ($CallerTemp) {
        [Environment]::SetEnvironmentVariable('GOCACHE', (Join-Path $overrideCache 'go-build'), 'Process')
        [Environment]::SetEnvironmentVariable('GOMODCACHE', (Join-Path $overrideCache 'go-mod'), 'Process')
        [Environment]::SetEnvironmentVariable('npm_config_cache', (Join-Path $overrideCache 'npm'), 'Process')
        [Environment]::SetEnvironmentVariable('GOTMPDIR', $callerGo, 'Process')
    }
    [Environment]::SetEnvironmentVariable('TEMP', (Join-Path $FixtureRoot 'original-temp'), 'Process')
    [Environment]::SetEnvironmentVariable('TMP', (Join-Path $FixtureRoot 'original-tmp'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GCM_INTERACTIVE', '1', 'Process')
    $before = Get-FixtureEnvironment
    $global:installedAppCacheFixtureState = @{
        Calls = 0
        ExpectedScript = Join-Path $project 'scripts/check-runtime-identity.mjs'
        Workspace = $FixtureRoot
        AtGate = $null
        TempExisted = $false
    }
    function global:node {
        param([Parameter(ValueFromRemainingArguments = $true)][object[]] $CommandArguments)
        $state = $global:installedAppCacheFixtureState
        $state.Calls++
        Assert-Equal $CommandArguments.Count 2 'unexpected node arguments'
        Assert-Equal ([string] $CommandArguments[0]) $state.ExpectedScript 'unexpected node command'
        Assert-Equal ([string] $CommandArguments[1]) $state.Workspace 'identity workspace argument changed'
        $state.AtGate = Get-FixtureEnvironment
        $state.TempExisted = Test-Path -LiteralPath $state.AtGate.GOTMPDIR -PathType Container
        $global:LASTEXITCODE = 17
    }
    function global:go { throw 'unexpected Go execution' }
    function global:git { throw 'unexpected Git execution' }
    function global:npm { throw 'unexpected npm execution' }

    $failure = $null
    try {
        & (Join-Path $project 'scripts/build-windows-installed-app.ps1') `
            -OutputRoot $output `
            -ChromiumRoot (Join-Path $FixtureRoot 'chromium') `
            -C2paToolPath (Join-Path $FixtureRoot 'unused-c2pa.txt')
    }
    catch { $failure = $_.Exception.Message }
    Assert-Equal $failure 'Runtime identity contract check failed before installed-app build.' 'builder error contract changed'
    $state = $global:installedAppCacheFixtureState
    Assert-Equal $state.Calls 1 'builder continued past the identity gate'
    Assert-True $state.TempExisted 'scratch must exist while the real wrapper is inside its gate'
    $expectedCache = if ($CallerTemp) { $overrideCache } else { $configuredCache }
    foreach ($entry in @(@('GOCACHE', 'go-build'), @('GOMODCACHE', 'go-mod'), @('npm_config_cache', 'npm'))) {
        Assert-Equal $state.AtGate[$entry[0]] (Join-Path $expectedCache $entry[1]) 'active cache selection changed'
    }
    Assert-Equal $state.AtGate.TEMP $state.AtGate.GOTMPDIR 'active TEMP must use selected scratch'
    Assert-Equal $state.AtGate.TMP $state.AtGate.GOTMPDIR 'active TMP must use selected scratch'
    Assert-Equal $state.AtGate.GIT_TERMINAL_PROMPT '0' 'Git prompts must be disabled inside the wrapper'
    Assert-Equal $state.AtGate.GCM_INTERACTIVE '0' 'credential prompts must be disabled inside the wrapper'

    # Observe restoration here, in the same process that executed the wrapper,
    # before the parent harness removes any fixture directories.
    $after = Get-FixtureEnvironment
    foreach ($name in $environmentNames) {
        Assert-Equal $after[$name] $before[$name] "environment restoration failed for $name"
    }
    $ownedRoot = Join-Path $project '.cache/source-build-temp'
    if ($CallerTemp) {
        Assert-Equal $state.AtGate.GOTMPDIR $callerGo 'caller GOTMPDIR was replaced'
        Assert-True (Test-Path -LiteralPath $callerGo -PathType Container) 'caller scratch was deleted'
    }
    else {
        Assert-True ($state.AtGate.GOTMPDIR.StartsWith($ownedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'owned scratch escaped its project root'
        Assert-True ([IO.Path]::GetFileName($state.AtGate.GOTMPDIR) -match '^windows-installed-app-[0-9]+-[0-9a-f]{32}$') 'owned scratch lacks a generated name'
        Assert-True (-not (Test-Path -LiteralPath $state.AtGate.GOTMPDIR)) 'owned scratch remains after wrapper failure'
    }
    $sibling = 'windows-installed-app-0-' + ('0' * 32)
    $remaining = @(Get-ChildItem -LiteralPath $ownedRoot -Force | Select-Object -ExpandProperty Name)
    Assert-Equal $remaining.Count 1 'scratch cleanup changed the owned parent or siblings'
    Assert-Equal $remaining[0] $sibling 'pre-existing scratch sibling was deleted'
    foreach ($relative in @('caller-go/preserve.txt', 'original-temp/preserve.txt', 'original-tmp/preserve.txt', 'output/preserve.txt', "AkuBrowser/.cache/source-build-temp/$sibling/preserve.txt")) {
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $FixtureRoot $relative))) 'preserve' "caller/output/sibling changed: $relative"
    }
    foreach ($cacheRoot in @($configuredCache, $overrideCache)) {
        foreach ($leaf in @('go-build', 'go-mod', 'npm')) {
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $cacheRoot "$leaf/preserve.txt"))) 'preserve' 'shared cache was changed'
        }
    }
    Assert-Equal (@(Get-ChildItem -LiteralPath $output -Force)).Count 1 'build artifacts were created after identity failure'
    [ordered]@{ status = 'ok'; callerTemp = [bool] $CallerTemp; gateCalls = $state.Calls; environmentVariablesVerified = $environmentNames.Count; error = $failure } | ConvertTo-Json -Compress
    exit 0
}

[IO.Directory]::CreateDirectory($fixtureBase) | Out-Null
$runRoot = Join-Path $fixtureBase ('installed-app-cache-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$builderPath = Join-Path $PSScriptRoot 'build-windows-installed-app.ps1'
$helperPath = Join-Path $PSScriptRoot 'source-cache.ps1'
$builderHash = (Get-FileHash -LiteralPath $builderPath -Algorithm SHA256).Hash
$helperHash = (Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash
$pwshPath = Join-Path $PSHOME 'pwsh.exe'
$results = @()
try {
    foreach ($withoutCleanup in @($false, $true)) {
        foreach ($caller in @($false, $true)) {
            $caseRoot = Join-Path $runRoot ("caller-$caller-without-cleanup-$withoutCleanup")
            $project = Join-Path $caseRoot 'AkuBrowser'
            $copies = @{
                'AkuBrowser/scripts/build-windows-installed-app.ps1' = $builderPath
                'AkuBrowser/scripts/source-cache.ps1' = $helperPath
                'AkuBrowser/release/release-manifest.json' = Join-Path $browserRoot 'release/release-manifest.json'
                'AkuBrowser/config/bridge-identities.json' = Join-Path $browserRoot 'config/bridge-identities.json'
                'AkuBridge/package.json' = Join-Path (Split-Path -Parent $browserRoot) 'AkuBridge/package.json'
                'AkuBridge/manifest.json' = Join-Path (Split-Path -Parent $browserRoot) 'AkuBridge/manifest.json'
                'AkuSidecar/internal/domain/types.go' = Join-Path (Split-Path -Parent $browserRoot) 'AkuSidecar/internal/domain/types.go'
            }
            foreach ($relative in $copies.Keys) {
                $destination = Join-Path $caseRoot $relative
                [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
                Copy-Item -LiteralPath $copies[$relative] -Destination $destination
            }
            $copiedBuilder = Join-Path $project 'scripts/build-windows-installed-app.ps1'
            Assert-Equal (Get-FileHash -LiteralPath $copiedBuilder -Algorithm SHA256).Hash $builderHash 'builder fixture bytes drifted'
            Assert-Equal (Get-FileHash -LiteralPath (Join-Path $project 'scripts/source-cache.ps1') -Algorithm SHA256).Hash $helperHash 'helper fixture bytes drifted'
            if ($withoutCleanup) {
                $text = [IO.File]::ReadAllText($copiedBuilder)
                $pattern = '(?m)^        Exit-SourceBuildEnvironment -Context \$sourceBuildEnvironment\r?$'
                Assert-Equal ([regex]::Matches($text, $pattern)).Count 1 'cleanup mutation must target exactly one wrapper call'
                $mutant = [regex]::Replace($text, $pattern, '        # Exit-SourceBuildEnvironment -Context $sourceBuildEnvironment (isolated mutation)')
                [IO.File]::WriteAllText($copiedBuilder, $mutant)
            }
            $sibling = 'windows-installed-app-0-' + ('0' * 32)
            $directories = @('caller-go', 'original-temp', 'original-tmp', 'output', "AkuBrowser/.cache/source-build-temp/$sibling")
            foreach ($cache in @('configured-cache', 'override-cache')) {
                foreach ($leaf in @('go-build', 'go-mod', 'npm')) { $directories += "$cache/$leaf" }
            }
            foreach ($relative in $directories) {
                $directory = Join-Path $caseRoot $relative
                [IO.Directory]::CreateDirectory($directory) | Out-Null
                [IO.File]::WriteAllText((Join-Path $directory 'preserve.txt'), 'preserve')
            }
            [IO.Directory]::CreateDirectory((Join-Path $caseRoot 'chromium')) | Out-Null
            [IO.File]::WriteAllText((Join-Path $caseRoot 'unused-c2pa.txt'), 'not executable')
            $cacheConfig = @{ schemaVersion = 1; root = Join-Path $caseRoot 'configured-cache' } | ConvertTo-Json -Compress
            [IO.File]::WriteAllText((Join-Path $project '.cache/source-build-cache.json'), $cacheConfig)
            $arguments = @('-NoProfile', '-File', $PSCommandPath, '-FixtureChild', '-FixtureRoot', $caseRoot)
            if ($caller) { $arguments += '-CallerTemp' }
            $output = (& $pwshPath @arguments 2>&1 | Out-String)
            $childExit = $LASTEXITCODE
            if ($withoutCleanup) {
                Assert-Equal $childExit 1 "missing wrapper cleanup must fail: $output"
                Assert-True ($output.Contains('environment restoration failed for')) "mutation failed outside the restoration assertion: $output"
            }
            else {
                Assert-Equal $childExit 0 "real wrapper fixture failed: $output"
                Assert-Equal ($output | ConvertFrom-Json).status 'ok' 'child fixture result missing'
            }
            $results += [ordered]@{ callerTemp = $caller; cleanupDisabledInCopy = $withoutCleanup; exitCode = $childExit; expectedResult = if ($withoutCleanup) { 'restoration assertion failure' } else { 'pass' } }
        }
    }
    Assert-Equal (Get-FileHash -LiteralPath $builderPath -Algorithm SHA256).Hash $builderHash 'production builder changed'
    Assert-Equal (Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash $helperHash 'production helper changed'
    [ordered]@{ status = 'ok'; positiveCases = 2; mutationExpectedFailures = 2; cases = $results; builderSHA256 = $builderHash; helperSHA256 = $helperHash } | ConvertTo-Json -Depth 5
}
finally {
    $cleanupTarget = Assert-OwnedFixture $runRoot
    Assert-True ([IO.Path]::GetDirectoryName($cleanupTarget).Equals($fixtureBase, [StringComparison]::OrdinalIgnoreCase)) 'fixture cleanup must target an immediate owned child'
    if (Test-Path -LiteralPath $cleanupTarget -PathType Container) { Remove-Item -LiteralPath $cleanupTarget -Recurse -Force }
}

exit 0
