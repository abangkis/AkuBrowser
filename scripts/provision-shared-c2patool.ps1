[CmdletBinding()]
param(
    [string] $SourcePath = ""
)

$ErrorActionPreference = 'Stop'
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$sidecarRoot = Join-Path $workspaceRoot 'AkuSidecar'
$release = Get-Content -LiteralPath (Join-Path $browserRoot 'release\release-manifest.json') -Raw | ConvertFrom-Json
$tool = $release.components.c2paTool
$workspaceSource = [string]$tool.workspaceSource
$expectedHash = ([string]$tool.sha256).ToLowerInvariant()

function Assert-NoReparsePathUnderRoot([string] $Path, [string] $Root, [string] $Description) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidatePath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if ($candidatePath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = ''
    } elseif ($candidatePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $candidatePath.Substring($rootPrefix.Length)
    } else {
        throw "$Description is outside its allowed root: $candidatePath"
    }

    $currentPath = $rootPath
    if (Test-Path -LiteralPath $currentPath) {
        $currentItem = Get-Item -LiteralPath $currentPath -Force
        if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description contains a reparse point: $currentPath"
        }
    }
    foreach ($segment in $relativePath.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $currentPath = Join-Path $currentPath $segment
        if (-not (Test-Path -LiteralPath $currentPath)) {
            break
        }
        $currentItem = Get-Item -LiteralPath $currentPath -Force
        if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description contains a reparse point: $currentPath"
        }
    }
}

$ancestor = [IO.DirectoryInfo]$workspaceRoot
$sharedRoot = $null
while ($null -ne $ancestor) {
    $candidate = Join-Path $ancestor.FullName 'SharedTemp'
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $candidateItem = Get-Item -LiteralPath $candidate -Force
        if (($candidateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Ancestor-owned SharedTemp is a reparse point: $candidate"
        }
        $sharedRoot = [IO.Path]::GetFullPath($candidate)
        break
    }
    $ancestor = $ancestor.Parent
}
if ($null -eq $sharedRoot) {
    throw "No ancestor-owned SharedTemp exists above $workspaceRoot"
}
$workspaceSourceSegments = $workspaceSource.Replace('\', '/').Split('/')
if ($workspaceSourceSegments.Count -lt 3 -or $workspaceSourceSegments[0] -ne '..' -or $workspaceSourceSegments[1] -ne 'SharedTemp') {
    throw "Pinned c2patool workspace source must be a path beneath ../SharedTemp: $workspaceSource"
}
$sharedRelativePath = $workspaceSourceSegments[2..($workspaceSourceSegments.Count - 1)] -join [IO.Path]::DirectorySeparatorChar
if ([string]::IsNullOrWhiteSpace($sharedRelativePath) -or $sharedRelativePath -match '(^|[\\/])\.\.?([\\/]|$)' -or [IO.Path]::IsPathRooted($sharedRelativePath)) {
    throw "Pinned c2patool workspace source is not a normalized SharedTemp-relative path: $workspaceSource"
}
$target = [IO.Path]::GetFullPath((Join-Path $sharedRoot $sharedRelativePath))
$sharedPrefix = $sharedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $target.StartsWith($sharedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Pinned shared c2patool path escapes the nearest SharedTemp: $target"
}
Assert-NoReparsePathUnderRoot $target $sharedRoot 'Shared c2patool target path'

if (Test-Path -LiteralPath $target) {
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "Shared c2patool target is not a file: $target"
    }
    $targetItem = Get-Item -LiteralPath $target -Force
    if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Shared c2patool target is a reparse point: $target"
    }
    $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    if ($targetHash -ne $expectedHash) {
        throw "Shared c2patool SHA-256 differs from the release manifest: $target"
    }
} else {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $SourcePath = Join-Path $sidecarRoot 'runtime\dev\c2patool.exe'
    }
    $SourcePath = [IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Pinned c2patool source was not found: $SourcePath"
    }
    $workspacePrefix = [IO.Path]::GetFullPath($workspaceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($SourcePath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Assert-NoReparsePathUnderRoot $SourcePath $workspaceRoot 'Pinned c2patool source path'
    }
    $sourceItem = Get-Item -LiteralPath $SourcePath -Force
    if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Pinned c2patool source is a reparse point: $SourcePath"
    }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash.ToLowerInvariant()
    if ($sourceHash -ne $expectedHash) {
        throw "Pinned c2patool source SHA-256 differs from the release manifest."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    $stagingPath = "$target.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $stagingPath
        $stagingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingPath).Hash.ToLowerInvariant()
        if ($stagingHash -ne $expectedHash) {
            throw "Staged c2patool SHA-256 differs from the release manifest."
        }
        if (Test-Path -LiteralPath $target) {
            throw "Shared c2patool target appeared before promotion: $target"
        }
        [IO.File]::Move($stagingPath, $target)
    } finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Force
        }
    }
    $targetItem = Get-Item -LiteralPath $target -Force
    if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Promoted shared c2patool is a reparse point: $target"
    }
    $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    if ($targetHash -ne $expectedHash) {
        throw "Shared c2patool SHA-256 differs from the release manifest: $target"
    }
}

$target
