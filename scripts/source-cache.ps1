function Get-SourceBuildCachePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Repository)

    $repositoryPath = [IO.Path]::GetFullPath($Repository)
    $cursor = [IO.DirectoryInfo]$repositoryPath
    $sharedTemp = $null
    while ($null -ne $cursor) {
        $candidate = Join-Path $cursor.FullName 'SharedTemp'
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $sharedTemp = $candidate
            break
        }
        $cursor = $cursor.Parent
    }
    if (-not $sharedTemp) { $sharedTemp = Join-Path $repositoryPath 'SharedTemp' }
    $cacheRoot = Join-Path $sharedTemp 'build-cache'
    $configuration = Join-Path $repositoryPath '.cache/source-build-cache.json'
    if (Test-Path -LiteralPath $configuration -PathType Leaf) {
        $config = Get-Content -Raw -LiteralPath $configuration | ConvertFrom-Json
        if ($config.schemaVersion -ne 1 -or $config.root -isnot [string] -or
            [string]::IsNullOrWhiteSpace($config.root) -or -not [IO.Path]::IsPathRooted($config.root) -or
            ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $config.root -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2})')) {
            throw 'Invalid source cache configuration: expected schemaVersion 1 and an absolute root.'
        }
        $cacheRoot = [IO.Path]::GetFullPath($config.root)
    }
    $defaults = @{
        GoBuild = @('GOCACHE', 'go-build')
        GoModules = @('GOMODCACHE', 'go-mod')
        Npm = @('npm_config_cache', 'npm')
    }
    $paths = @{}
    foreach ($key in $defaults.Keys) {
        $value = [Environment]::GetEnvironmentVariable($defaults[$key][0], 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = Join-Path $cacheRoot $defaults[$key][1]
        }
        $paths[$key] = [IO.Path]::GetFullPath($value)
    }
    [pscustomobject]$paths
}

function Enter-SourceBuildEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$RunName
    )

    $repositoryPath = [IO.Path]::GetFullPath($Repository)
    $names = @('GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'npm_config_cache', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE')
    $saved = @{}
    foreach ($name in $names) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $cachePaths = Get-SourceBuildCachePaths -Repository $repositoryPath
    $configuredTemp = [Environment]::GetEnvironmentVariable('GOTMPDIR', 'Process')
    $ownsTemp = [string]::IsNullOrWhiteSpace($configuredTemp)
    $tempBase = Join-Path $repositoryPath '.cache/source-build-temp'
    $safeRunName = [regex]::Replace($RunName, '[^A-Za-z0-9_-]', '-')
    if ([string]::IsNullOrWhiteSpace($safeRunName)) { $safeRunName = 'source-build' }
    if ($ownsTemp) {
        $tempDirectory = Join-Path $tempBase ('{0}-{1}-{2}' -f $safeRunName, $PID, [Guid]::NewGuid().ToString('N'))
    }
    else {
        $tempDirectory = [IO.Path]::GetFullPath($configuredTemp)
    }
    $context = [pscustomobject]@{
        Repository = $repositoryPath
        CachePaths = $cachePaths
        TempDirectory = $tempDirectory
        OwnsTempDirectory = $ownsTemp
        SavedEnvironment = $saved
    }

    try {
        foreach ($directory in @($cachePaths.GoBuild, $cachePaths.GoModules, $cachePaths.Npm, $tempDirectory)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }
        [Environment]::SetEnvironmentVariable('GOCACHE', $cachePaths.GoBuild, 'Process')
        [Environment]::SetEnvironmentVariable('GOMODCACHE', $cachePaths.GoModules, 'Process')
        [Environment]::SetEnvironmentVariable('npm_config_cache', $cachePaths.Npm, 'Process')
        [Environment]::SetEnvironmentVariable('GOTMPDIR', $tempDirectory, 'Process')
        [Environment]::SetEnvironmentVariable('TEMP', $tempDirectory, 'Process')
        [Environment]::SetEnvironmentVariable('TMP', $tempDirectory, 'Process')
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0', 'Process')
        [Environment]::SetEnvironmentVariable('GCM_INTERACTIVE', '0', 'Process')
        return $context
    }
    catch {
        Exit-SourceBuildEnvironment -Context $context
        throw
    }
}

function Exit-SourceBuildEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$Context)

    try {
        foreach ($name in $Context.SavedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $Context.SavedEnvironment[$name], 'Process')
        }
    }
    finally {
        if ($Context.OwnsTempDirectory -and -not [string]::IsNullOrWhiteSpace($Context.TempDirectory)) {
            $repositoryPath = [IO.Path]::GetFullPath($Context.Repository)
            $tempRoot = [IO.Path]::GetFullPath((Join-Path $repositoryPath '.cache/source-build-temp'))
            $trimChars = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $tempPrefix = $tempRoot.TrimEnd($trimChars) + [IO.Path]::DirectorySeparatorChar
            $candidate = [IO.Path]::GetFullPath($Context.TempDirectory)
            $leaf = [IO.Path]::GetFileName($candidate)
            $cachePath = Join-Path $repositoryPath '.cache'
            $cacheItem = Get-Item -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue
            $tempRootItem = Get-Item -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue
            $candidateItem = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
            $reparsePoint = [IO.FileAttributes]::ReparsePoint
            $insideOwnedRoot = $candidate.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetDirectoryName($candidate).Equals($tempRoot, [StringComparison]::OrdinalIgnoreCase)
            $hasGeneratedName = $leaf -match '^[A-Za-z0-9_-]+-[0-9]+-[0-9a-f]{32}$'
            $safeDirectories = $null -ne $cacheItem -and $null -ne $tempRootItem -and $null -ne $candidateItem -and
                (($cacheItem.Attributes -band $reparsePoint) -eq 0) -and
                (($tempRootItem.Attributes -band $reparsePoint) -eq 0) -and
                (($candidateItem.Attributes -band $reparsePoint) -eq 0)
            if ($insideOwnedRoot -and $hasGeneratedName -and $safeDirectories -and $candidateItem.PSIsContainer) {
                Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}