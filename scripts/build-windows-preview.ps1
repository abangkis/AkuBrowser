[CmdletBinding()]
param(
    [string] $OutputRoot = "",
    [string] $C2paToolPath = "",
    [switch] $SkipValidation,
    [switch] $AllowDirty
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$releaseManifestPath = Join-Path $browserRoot "release\release-manifest.json"
$bridgeIdentityRegistryPath = Join-Path $browserRoot "config\bridge-identities.json"
if ([string]::IsNullOrWhiteSpace($C2paToolPath)) {
    $C2paToolPath = Join-Path $sidecarRoot "runtime\dev\c2patool.exe"
}
$C2paToolPath = [IO.Path]::GetFullPath($C2paToolPath)

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
$bridgeIdentityRegistry = Read-Json $bridgeIdentityRegistryPath
$bridgePackage = Read-Json (Join-Path $bridgeRoot "package.json")
$bridgeManifest = Read-Json (Join-Path $bridgeRoot "manifest.json")
$sidecarDomain = Get-Content -LiteralPath (Join-Path $sidecarRoot "internal\domain\types.go") -Raw

$bridgeIdentityProfile = [string]$release.distribution.chromeStore.bridgeIdentityProfile
$bridgeIdentityProperty = $bridgeIdentityRegistry.profiles.PSObject.Properties[$bridgeIdentityProfile]
Assert-True ($bridgeIdentityRegistry.schemaVersion -eq 1) "Unsupported Bridge identity registry schema."
Assert-True (-not [string]::IsNullOrWhiteSpace($bridgeIdentityProfile) -and $null -ne $bridgeIdentityProperty) "The release manifest must select an existing Bridge identity profile."
$bridgeIdentity = $bridgeIdentityProperty.Value
$bridgeExtensionId = [string]$bridgeIdentity.extensionId
$bridgeExtensionOrigin = "chrome-extension://$bridgeExtensionId/"
Assert-True ($bridgeIdentity.distribution -eq "chrome-web-store") "The Windows release must use a Chrome Web Store Bridge identity."
Assert-True ($bridgeExtensionId -match '^[a-p]{32}$') "The production Bridge identity must declare an exact Chrome Web Store extension ID."
Assert-True ($null -eq $release.distribution.chromeStore.PSObject.Properties["extensionId"]) "The release manifest must not duplicate the Bridge extension ID."
Assert-True ($null -eq $release.distribution.chromeStore.PSObject.Properties["extensionOrigin"]) "The release manifest must not duplicate the Bridge extension origin."

Assert-True ($release.distribution.authorityRepository -eq "AkuBrowser") "AkuBrowser is not the declared distribution authority."
Assert-True ($release.distribution.windows.architecture -eq "x64") "The release manifest does not describe Windows x64."
Assert-True ($release.distribution.windows.format -eq "portable-zip") "The release manifest does not describe a portable ZIP."
Assert-True ($release.components.akuBridge.version -eq $bridgePackage.version) "AkuBridge package version differs from the release tuple."
Assert-True ($release.components.akuBridge.chromeVersion -eq $bridgeManifest.version) "AkuBridge Chrome version differs from the release tuple."
Assert-True ($release.components.akuBridge.version -eq $bridgeManifest.version_name) "AkuBridge product version differs from its manifest version name."
Assert-True ($sidecarDomain -match ('ApplicationVersion\s*=\s*"' + [regex]::Escape($release.components.akuSidecar.version) + '"')) "AkuSidecar version differs from the release tuple."
Assert-True (Test-Path -LiteralPath $C2paToolPath -PathType Leaf) "The required Windows c2patool source was not found: $C2paToolPath"
$c2paToolVersionText = (& $C2paToolPath --version | Out-String).Trim()
Assert-True ($LASTEXITCODE -eq 0) "The selected c2patool binary could not report its version."
Assert-True ($c2paToolVersionText -eq "c2patool $($release.components.c2paTool.version)") "c2patool version differs from the release tuple: $c2paToolVersionText"
$c2paToolSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $C2paToolPath).Hash.ToLowerInvariant()
Assert-True ($c2paToolSha256 -eq $release.components.c2paTool.sha256) "c2patool SHA-256 differs from the pinned release binary."

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
$c2paToolOutput = Join-Path $artifactRoot "c2patool.exe"
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
Copy-Item -LiteralPath $C2paToolPath -Destination $c2paToolOutput
$c2paLicenseOutput = Join-Path $artifactRoot "third-party\c2patool"
New-Item -ItemType Directory -Force -Path $c2paLicenseOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $browserRoot "release\third-party\c2patool\LICENSE-MIT") -Destination $c2paLicenseOutput
Copy-Item -LiteralPath (Join-Path $browserRoot "release\third-party\c2patool\THIRD-PARTY-NOTICE.md") -Destination $c2paLicenseOutput
$c2paApacheLicense = (Get-Content -LiteralPath (Join-Path $browserRoot "LICENSE") -Raw).
    Replace("`r`n", "`n").
    Replace("Copyright [yyyy] [name of copyright owner]", "Copyright 2020 Adobe").
    Replace(
        "      `"Work`" shall mean the work of authorship, whether in Source or Object`n" +
        "      form, made available under the License, as indicated by a copyright`n" +
        "      notice that is included in or attached to the work (an example is`n" +
        "      provided in the Appendix below).",
        "      `"Work`" shall mean the work of authorship, whether in Source or`n" +
        "      Object form, made available under the License, as indicated by a`n" +
        "      copyright notice that is included in or attached to the work`n" +
        "      (an example is provided in the Appendix below)."
    )
Write-Utf8NoBom (Join-Path $c2paLicenseOutput "LICENSE-APACHE") $c2paApacheLicense

$configDirectory = Join-Path $artifactRoot "config"
New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
$packageConfig = Read-Json (Join-Path $sidecarRoot "config\sidecar.json")
$packageConfig.database.path = "data/aku-sidecar.db"
$packageConfig.reasoning.executable = ""
$packageConfig.bridge.trustedExtensionOrigins = @($bridgeExtensionOrigin)
Write-Utf8NoBom (Join-Path $configDirectory "sidecar.json") ($packageConfig | ConvertTo-Json -Depth 10)

$schemaOutput = Join-Path $artifactRoot "schemas"
New-Item -ItemType Directory -Force -Path $schemaOutput | Out-Null
Get-ChildItem -LiteralPath (Join-Path $sidecarRoot "schemas") -Filter "*.schema.json" -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $schemaOutput }

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
    bridgeIdentity = [ordered]@{
        profile = $bridgeIdentityProfile
        distribution = [string]$bridgeIdentity.distribution
        authority = "config/bridge-identities.json"
        extensionOrigin = $bridgeExtensionOrigin
    }
    bundledTools = [ordered]@{
        c2paTool = [ordered]@{
            version = $release.components.c2paTool.version
            sha256 = $c2paToolSha256
            file = "c2patool.exe"
            sourcePolicy = $release.components.c2paTool.sourcePolicy
            workspaceSource = $release.components.c2paTool.workspaceSource
            licenses = @(
                "third-party/c2patool/LICENSE-MIT",
                "third-party/c2patool/LICENSE-APACHE",
                "third-party/c2patool/THIRD-PARTY-NOTICE.md"
            )
        }
    }
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
    c2paToolBytes = (Get-Item -LiteralPath $c2paToolOutput).Length
    c2paToolVersion = $release.components.c2paTool.version
    c2paToolSha256 = $c2paToolSha256
    bridgeFiles = @($bridgeVerification.files).Count
    sourceCommits = $sourceCommits
    sourceDirty = @($dirtyRepositories)
    bridgeIdentityProfile = $bridgeIdentityProfile
    bridgeExtensionOrigin = $bridgeExtensionOrigin
} | ConvertTo-Json -Depth 8
