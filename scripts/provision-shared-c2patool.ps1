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
$target = [IO.Path]::GetFullPath((Join-Path $workspaceRoot ([string]$tool.workspaceSource)))
$expectedHash = ([string]$tool.sha256).ToLowerInvariant()

$ancestor = [IO.DirectoryInfo]$workspaceRoot
$sharedRoot = $null
while ($null -ne $ancestor) {
    $candidate = Join-Path $ancestor.FullName 'SharedTemp'
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $sharedRoot = [IO.Path]::GetFullPath($candidate)
        break
    }
    $ancestor = $ancestor.Parent
}
if ($null -eq $sharedRoot) {
    throw "No ancestor-owned SharedTemp exists above $workspaceRoot"
}
$sharedPrefix = $sharedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $target.StartsWith($sharedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Pinned shared c2patool path escapes the nearest SharedTemp: $target"
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $SourcePath = Join-Path $sidecarRoot 'runtime\dev\c2patool.exe'
    }
    $SourcePath = [IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Pinned c2patool source was not found: $SourcePath"
    }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash.ToLowerInvariant()
    if ($sourceHash -ne $expectedHash) {
        throw "Pinned c2patool source SHA-256 differs from the release manifest."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $SourcePath -Destination $target
}

$targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
if ($targetHash -ne $expectedHash) {
    throw "Shared c2patool SHA-256 differs from the release manifest: $target"
}

$target
