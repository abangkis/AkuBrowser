[CmdletBinding()]
param(
    [string] $OutputRoot = "",
    [switch] $SkipValidation,
    [switch] $AllowDirty
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$releaseManifestPath = Join-Path $browserRoot "release\release-manifest.json"

function Read-Json([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-RelativeArtifactPath([string] $BasePath, [string] $Path) {
    $baseUri = [Uri]([IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri][IO.Path]::GetFullPath($Path)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

function Invoke-Git([string] $Repository, [string[]] $Arguments) {
    $value = & git -C $Repository @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Repository"
    }
    return ($value | Out-String).Trim()
}

function Reset-ArtifactPath([string] $Path, [string] $AllowedRoot, [switch] $Directory) {
    $absolutePath = [IO.Path]::GetFullPath($Path)
    $absoluteRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $prefix = $absoluteRoot + [IO.Path]::DirectorySeparatorChar
    Assert-True ($absolutePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Refusing to replace a path outside the artifact root: $absolutePath"
    if (Test-Path -LiteralPath $absolutePath) {
        Remove-Item -LiteralPath $absolutePath -Recurse -Force
    }
    if ($Directory) {
        New-Item -ItemType Directory -Force -Path $absolutePath | Out-Null
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $browserRoot "artifacts"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$release = Read-Json $releaseManifestPath
$bridgePackage = Read-Json (Join-Path $bridgeRoot "package.json")
$bridgeManifest = Read-Json (Join-Path $bridgeRoot "manifest.json")
$sidecarDomain = Get-Content -LiteralPath (Join-Path $sidecarRoot "internal\domain\types.go") -Raw

Assert-True ($release.distribution.authorityRepository -eq "AkuBrowser") "AkuBrowser is not the declared distribution authority."
Assert-True ($release.distribution.windows.architecture -eq "x64") "The release manifest does not describe Windows x64."
Assert-True ($release.distribution.windows.format -eq "portable-zip") "The release manifest does not describe a portable ZIP."
Assert-True ($release.components.akuBridge.version -eq $bridgePackage.version) "AkuBridge package version differs from the release tuple."
Assert-True ($release.components.akuBridge.chromeVersion -eq $bridgeManifest.version) "AkuBridge Chrome version differs from the release tuple."
Assert-True ($release.components.akuBridge.version -eq $bridgeManifest.version_name) "AkuBridge product version differs from its manifest version name."
Assert-True ($sidecarDomain -match ('ApplicationVersion\s*=\s*"' + [regex]::Escape($release.components.akuSidecar.version) + '"')) "AkuSidecar version differs from the release tuple."

$sourceRepositories = [ordered]@{
    akuBrowser = $browserRoot
    akuSidecar = $sidecarRoot
    akuBridge = $bridgeRoot
}
$sourceCommits = [ordered]@{}
$dirtyRepositories = @()
foreach ($entry in $sourceRepositories.GetEnumerator()) {
    $sourceCommits[$entry.Key] = Invoke-Git $entry.Value @("rev-parse", "HEAD")
    $status = Invoke-Git $entry.Value @("status", "--porcelain")
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        $dirtyRepositories += $entry.Key
    }
}
if ($dirtyRepositories.Count -gt 0 -and -not $AllowDirty) {
    throw "Release sources must be clean. Dirty repositories: $($dirtyRepositories -join ', '). Use -AllowDirty only for a local candidate."
}

if (-not $SkipValidation) {
    & (Join-Path $PSScriptRoot "check.ps1") -DistributionOnly
    if ($LASTEXITCODE -ne 0) { throw "Distribution component validation failed." }
}

$artifactName = "AkuBrowser-$($release.version)-windows-x64"
$artifactRoot = Join-Path $OutputRoot $artifactName
$zipPath = Join-Path $OutputRoot "$artifactName.zip"
$zipChecksumPath = "$zipPath.sha256"
Reset-ArtifactPath $artifactRoot $OutputRoot -Directory
Reset-ArtifactPath $zipPath $OutputRoot
Reset-ArtifactPath $zipChecksumPath $OutputRoot

$sidecarOutput = Join-Path $artifactRoot "AkuSidecar.exe"
$cacheRoot = Join-Path $workspaceRoot ".go-cache"
$savedEnvironment = @{
    GOOS = $env:GOOS
    GOARCH = $env:GOARCH
    CGO_ENABLED = $env:CGO_ENABLED
    GOCACHE = $env:GOCACHE
    GOMODCACHE = $env:GOMODCACHE
    GOTMPDIR = $env:GOTMPDIR
}
try {
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    $env:GOCACHE = Join-Path $cacheRoot "build"
    $env:GOMODCACHE = Join-Path $cacheRoot "mod"
    $env:GOTMPDIR = Join-Path $cacheRoot "tmp"
    foreach ($directory in @($env:GOCACHE, $env:GOMODCACHE, $env:GOTMPDIR)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    Push-Location $sidecarRoot
    try {
        & go build -trimpath -ldflags "-s -w" -o $sidecarOutput .\cmd\akusidecar
        if ($LASTEXITCODE -ne 0) { throw "AkuSidecar release build failed." }
    }
    finally { Pop-Location }
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        if ($null -eq $savedEnvironment[$name]) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -Path "Env:$name" -Value $savedEnvironment[$name]
        }
    }
}

$configDirectory = Join-Path $artifactRoot "config"
New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
$packageConfig = Read-Json (Join-Path $sidecarRoot "config\sidecar.json")
$packageConfig.database.path = "data/aku-sidecar.db"
$packageConfig.reasoning.executable = "codex.exe"
Write-Utf8NoBom (Join-Path $configDirectory "sidecar.json") ($packageConfig | ConvertTo-Json -Depth 10)

$bridgeVerificationText = & node (Join-Path $bridgeRoot "scripts\verify-extension-package.mjs")
if ($LASTEXITCODE -ne 0) { throw "AkuBridge package verification failed." }
$bridgeVerification = ($bridgeVerificationText | Out-String) | ConvertFrom-Json
Assert-True ($bridgeVerification.version -eq $release.components.akuBridge.version) "Verified AkuBridge version differs from the release tuple."

$bridgeOutput = Join-Path $artifactRoot "AkuBridge"
New-Item -ItemType Directory -Force -Path $bridgeOutput | Out-Null
foreach ($file in $bridgeVerification.files) {
    $source = Join-Path $bridgeRoot $file.path
    $destination = Join-Path $bridgeOutput $file.path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

Copy-Item -LiteralPath $releaseManifestPath -Destination (Join-Path $artifactRoot "release-manifest.json")
Copy-Item -LiteralPath (Join-Path $browserRoot "release\windows\Start-AkuBrowser.ps1") -Destination $artifactRoot
Copy-Item -LiteralPath (Join-Path $browserRoot "release\windows\Start-AkuBrowser.cmd") -Destination $artifactRoot
Copy-Item -LiteralPath (Join-Path $browserRoot "release\windows\README.md") -Destination (Join-Path $artifactRoot "README.md")

$artifactManifest = [ordered]@{
    schemaVersion = 1
    product = $release.product
    version = $release.version
    channel = $release.channel
    target = "windows-x64"
    format = "portable-zip"
    builtAtUtc = [DateTime]::UtcNow.ToString("o")
    sourceCommits = $sourceCommits
    sourceDirty = @($dirtyRepositories)
    components = $release.components
    akuBridgeFingerprint = $bridgeVerification.fingerprint
}
Write-Utf8NoBom (Join-Path $artifactRoot "artifact-manifest.json") ($artifactManifest | ConvertTo-Json -Depth 10)

$checksumPath = Join-Path $artifactRoot "checksums.sha256"
$checksumLines = Get-ChildItem -LiteralPath $artifactRoot -Recurse -File |
    Where-Object { $_.FullName -ne $checksumPath } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = Get-RelativeArtifactPath $artifactRoot $_.FullName
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
$checksumLines | Set-Content -LiteralPath $checksumPath -Encoding ASCII

Compress-Archive -Path (Join-Path $artifactRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
"$zipHash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath $zipChecksumPath -Encoding ASCII

[ordered]@{
    status = "ok"
    candidate = [bool]$AllowDirty
    version = $release.version
    artifactDirectory = $artifactRoot
    zip = $zipPath
    zipSha256 = $zipHash
    sidecarBytes = (Get-Item -LiteralPath $sidecarOutput).Length
    bridgeFiles = @($bridgeVerification.files).Count
    sourceCommits = $sourceCommits
    sourceDirty = @($dirtyRepositories)
} | ConvertTo-Json -Depth 8
