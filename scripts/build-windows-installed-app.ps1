[CmdletBinding()]
param(
    [string] $OutputRoot = "",
    [string] $ChromiumRoot = "",
    [string] $C2paToolPath = "",
    [switch] $AllowDirty
)

$ErrorActionPreference = "Stop"

$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$launcherRoot = Join-Path $browserRoot "launcher"
$releaseManifestPath = Join-Path $browserRoot "release\release-manifest.json"
$bridgeIdentityRegistryPath = Join-Path $browserRoot "config\bridge-identities.json"
$sidecarConfigPath = Join-Path $sidecarRoot "config\sidecar.json"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Required JSON file was not found: $Path"
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-FullPath([string] $Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Get-RelativeArtifactPath([string] $BasePath, [string] $Path) {
    $base = (Get-FullPath $BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $baseUri = [Uri]($base + [IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri](Get-FullPath $Path)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace("\", "/")
}

function Assert-ContainedPath([string] $Path, [string] $Root, [string] $Description) {
    $absolutePath = Get-FullPath $Path
    $absoluteRoot = (Get-FullPath $Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $prefix = $absoluteRoot + [IO.Path]::DirectorySeparatorChar
    Assert-True $absolutePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) "$Description is outside its allowed root: $absolutePath"
    return $absolutePath
}

function Reset-ArtifactPath([string] $Path, [string] $AllowedRoot) {
    $absolutePath = Assert-ContainedPath $Path $AllowedRoot "Artifact path"
    if (Test-Path -LiteralPath $absolutePath) {
        Remove-Item -LiteralPath $absolutePath -Recurse -Force
    }
}

function Assert-PortableRelativePath([string] $Path, [string] $Description) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($Path)) "$Description is empty"
    Assert-True (-not $Path.Contains("\")) "$Description must use forward slashes: $Path"
    Assert-True (-not [IO.Path]::IsPathRooted($Path)) "$Description must be relative: $Path"
    $native = [IO.Path]::GetFullPath((Join-Path "C:\" $Path))
    $normalized = $native.Substring(3).Replace("\", "/")
    Assert-True ($normalized -eq $Path -and $Path -ne "." -and $Path -ne ".." -and -not $Path.StartsWith("../")) "$Description is not normalized or contains traversal: $Path"
}

function Assert-NoReparsePoints([string] $Root, [string] $Description) {
    $entries = Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop
    foreach ($entry in $entries) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description contains a symbolic link or reparse point: $($entry.FullName)"
        }
    }
}

function Invoke-Git([string] $Repository, [string[]] $Arguments) {
    $value = & git -c ("safe.directory=" + $Repository) -C $Repository @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Repository"
    }
    return ($value | Out-String).Trim()
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Copy-VerifiedFile([string] $SourceRoot, [string] $DestinationRoot, [string] $RelativePath) {
    Assert-PortableRelativePath $RelativePath "Verified Bridge file path"
    $source = Join-Path $SourceRoot $RelativePath
    $destination = Join-Path $DestinationRoot $RelativePath
    Assert-True (Test-Path -LiteralPath $source -PathType Leaf) "Verified Bridge file is missing: $RelativePath"
    $sourceItem = Get-Item -LiteralPath $source -Force
    Assert-True (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Verified Bridge file is a reparse point: $RelativePath"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Get-SourceState {
    $repositories = [ordered]@{
        akuBrowser = $browserRoot
        akuSidecar = $sidecarRoot
        akuBridge = $bridgeRoot
    }
    $commits = [ordered]@{}
    $dirty = @()
    foreach ($entry in $repositories.GetEnumerator()) {
        $commits[$entry.Key] = Invoke-Git $entry.Value @("rev-parse", "HEAD")
        $status = Invoke-Git $entry.Value @("status", "--porcelain")
        if (-not [string]::IsNullOrWhiteSpace($status)) { $dirty += $entry.Key }
    }
    if ($dirty.Count -gt 0 -and -not $AllowDirty) {
        throw "Release sources must be clean. Dirty repositories: $($dirty -join ', '). Use -AllowDirty only for a local candidate."
    }
    return [ordered]@{ commits = $commits; dirty = @($dirty) }
}

Assert-True (Test-Path -LiteralPath $bridgeRoot -PathType Container) "AkuBridge source root was not found: $bridgeRoot"
Assert-True (Test-Path -LiteralPath $sidecarRoot -PathType Container) "AkuSidecar source root was not found: $sidecarRoot"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $browserRoot "artifacts"
}
if ([string]::IsNullOrWhiteSpace($ChromiumRoot)) {
    $ChromiumRoot = Join-Path $sidecarRoot "runtime\chromium"
}
if ([string]::IsNullOrWhiteSpace($C2paToolPath)) {
    $c2paSource = (Read-Json $releaseManifestPath).components.c2paTool.workspaceSource
    $C2paToolPath = Join-Path $workspaceRoot $c2paSource
}
$OutputRoot = Get-FullPath $OutputRoot
$ChromiumRoot = Get-FullPath $ChromiumRoot
$C2paToolPath = Get-FullPath $C2paToolPath
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$release = Read-Json $releaseManifestPath
$registry = Read-Json $bridgeIdentityRegistryPath
$bridgePackage = Read-Json (Join-Path $bridgeRoot "package.json")
$bridgeManifest = Read-Json (Join-Path $bridgeRoot "manifest.json")
$sidecarDomain = Get-Content -LiteralPath (Join-Path $sidecarRoot "internal\domain\types.go") -Raw
$installedApp = $release.distribution.installedApp
Assert-True ($null -ne $installedApp) "The release manifest must declare the staged installed-app builder."
Assert-True ([string]$installedApp.status -eq "staged-builder") "installedApp must be marked staged-builder, not shipped."
Assert-True ([string]$installedApp.bridgeIdentityProfile -eq "production-app") "installedApp must select production-app."
Assert-True ([string]$installedApp.installerStatus -eq "not-shipped") "installedApp must not claim a shipped installer."
Assert-True ([int]$installedApp.database.currentSchemaVersion -gt 0) "installedApp must declare the current Sidecar database schema."
Assert-True ([string]$installedApp.database.rollbackStatus -eq "not-implemented") "installedApp must not claim database rollback before tuple rollback exists."

& node (Join-Path $PSScriptRoot "check-runtime-identity.mjs") $workspaceRoot | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Runtime identity contract check failed before installed-app build." }
& node (Join-Path $PSScriptRoot "validate-bridge-identity-registry.mjs") $bridgeIdentityRegistryPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Bridge identity registry validation failed." }

$identityProperty = $registry.profiles.PSObject.Properties["production-app"]
Assert-True ($registry.schemaVersion -eq 2 -and $null -ne $identityProperty) "production-app is missing from the Bridge identity registry."
$identity = $identityProperty.Value
Assert-True ([string]$identity.environment -eq "production") "production-app must be a production identity."
Assert-True ([string]$identity.distribution -eq "installed-app") "production-app must declare installed-app distribution."
Assert-True ([string]$identity.runtimeLifecycle -eq "managed") "production-app must declare managed lifecycle."
Assert-True ([string]$identity.runtimeAcquisition -eq "bundled-installer") "production-app must declare bundled-installer acquisition."
$extensionId = [string]$identity.extensionId
Assert-True ($extensionId -match '^[a-p]{32}$') "production-app must declare an exact Chrome extension ID."
Assert-True ($extensionId -ne [string]$registry.profiles.'production-offline'.extensionId) "production-app must be distinct from production-offline."
$extensionOrigin = "chrome-extension://$extensionId/"

Assert-True ([string]$release.distribution.authorityRepository -eq "AkuBrowser") "AkuBrowser is not the declared distribution authority."
Assert-True ([string]$release.distribution.windows.architecture -eq "x64") "The release manifest does not describe Windows x64."
Assert-True ([string]$release.components.akuBridge.version -eq [string]$bridgePackage.version) "AkuBridge package version differs from the release tuple."
Assert-True ([string]$release.components.akuBridge.chromeVersion -eq [string]$bridgeManifest.version) "AkuBridge Chrome version differs from the release tuple."
Assert-True ([string]$release.components.akuBridge.version -eq [string]$bridgeManifest.version_name) "AkuBridge product version differs from its manifest version name."
Assert-True ($sidecarDomain -match ('ApplicationVersion\s*=\s*"' + [regex]::Escape([string]$release.components.akuSidecar.version) + '"')) "AkuSidecar version differs from the release tuple."

$sourceState = Get-SourceState
Assert-NoReparsePoints $bridgeRoot "AkuBridge source"
$pinPath = Join-Path $ChromiumRoot "pin.json"
$chromiumPinExecutableRelative = "bin/chrome.exe"
$chromiumExecutableRelative = "chromium/bin/chrome.exe"
$chromiumExecutablePath = Join-Path $ChromiumRoot ([IO.Path]::Combine("bin", "chrome.exe"))
Assert-True (Test-Path -LiteralPath $ChromiumRoot -PathType Container) "Chromium root was not found: $ChromiumRoot"
Assert-True (Test-Path -LiteralPath $pinPath -PathType Leaf) "Chromium pin.json was not found: $pinPath"
Assert-True (Test-Path -LiteralPath $chromiumExecutablePath -PathType Leaf) "Pinned Chromium executable was not found: $chromiumExecutablePath"
Assert-NoReparsePoints $ChromiumRoot "Pinned Chromium source"
$pin = Read-Json $pinPath
Assert-True ($pin.schemaVersion -eq 1 -and $pin.component -eq "AkuBrowserAppShellChromium" -and $pin.channel -eq "stable" -and $pin.platform -eq "win64") "Chromium pin metadata is not the supported stable win64 pin."
Assert-True ([string]$pin.executable.Replace("\", "/") -eq $chromiumPinExecutableRelative) "Chromium pin executable path must be bin/chrome.exe."
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$pin.version)) "Chromium pin version is empty."
$chromiumHash = Get-Sha256 $chromiumExecutablePath
Assert-True ($chromiumHash -eq ([string]$pin.executableSha256).ToLowerInvariant()) "Pinned Chromium executable SHA-256 does not match pin.json."
$chromiumVersionInfo = (Get-Item -LiteralPath $chromiumExecutablePath -Force).VersionInfo
Assert-True ([string]$chromiumVersionInfo.FileVersion -eq [string]$pin.version) "Pinned Chromium executable version differs from pin.json."
$chromiumSourceFiles = @(Get-ChildItem -LiteralPath $ChromiumRoot -Recurse -File -Force)
Assert-True ($chromiumSourceFiles.Count -gt 0) "Pinned Chromium source is empty."

$c2paPin = $release.components.c2paTool
Assert-True (Test-Path -LiteralPath $C2paToolPath -PathType Leaf) "The required Windows c2patool source was not found: $C2paToolPath"
$c2paSourceItem = Get-Item -LiteralPath $C2paToolPath -Force
Assert-True (($c2paSourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "The selected c2patool source is a reparse point: $C2paToolPath"
$c2paHash = Get-Sha256 $C2paToolPath
Assert-True ($c2paHash -eq ([string]$c2paPin.sha256).ToLowerInvariant()) "c2patool SHA-256 differs from the release pin."
$c2paVersionText = (& $C2paToolPath --version | Out-String).Trim()
Assert-True ($LASTEXITCODE -eq 0 -and $c2paVersionText -eq "c2patool $($c2paPin.version)") "c2patool version differs from the release pin: $c2paVersionText"

$artifactName = "AkuBrowser-$($release.version)-windows-x64-installed-app"
$artifactRoot = Join-Path $OutputRoot $artifactName
$versionRoot = Join-Path $artifactRoot (Join-Path "runtime\versions" ([string]$release.version))
$artifactCreated = $false
try {
    Reset-ArtifactPath $artifactRoot $OutputRoot
    New-Item -ItemType Directory -Force -Path $versionRoot | Out-Null
    $artifactCreated = $true

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
            & go build -trimpath -ldflags "-s -w" -o (Join-Path $versionRoot "AkuSidecar.exe") .\cmd\akusidecar
            if ($LASTEXITCODE -ne 0) { throw "AkuSidecar release build failed." }
        }
        finally { Pop-Location }
        Push-Location $launcherRoot
        try {
            & go build -trimpath -ldflags "-s -w" -o (Join-Path $artifactRoot "AkuBrowserLauncher.exe") .\cmd\AkuBrowserLauncher
            if ($LASTEXITCODE -ne 0) { throw "AkuBrowserLauncher release build failed." }
        }
        finally { Pop-Location }
    }
    finally {
        foreach ($name in $savedEnvironment.Keys) {
            if ($null -eq $savedEnvironment[$name]) {
                Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -LiteralPath ("Env:" + $name) -Value $savedEnvironment[$name]
            }
        }
    }

    $versionC2pa = Join-Path $versionRoot "c2patool.exe"
    Copy-Item -LiteralPath $C2paToolPath -Destination $versionC2pa -Force
    $licenseDirectory = Join-Path $versionRoot "third-party\c2patool"
    New-Item -ItemType Directory -Force -Path $licenseDirectory | Out-Null
    $licenseSource = Join-Path $browserRoot "release\third-party\c2patool"
    Copy-Item -LiteralPath (Join-Path $licenseSource "LICENSE-MIT") -Destination $licenseDirectory -Force
    Copy-Item -LiteralPath (Join-Path $licenseSource "THIRD-PARTY-NOTICE.md") -Destination $licenseDirectory -Force
    $apacheLicense = (Get-Content -LiteralPath (Join-Path $browserRoot "LICENSE") -Raw).
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
    Write-Utf8NoBom (Join-Path $licenseDirectory "LICENSE-APACHE") $apacheLicense

    $schemaDirectory = Join-Path $versionRoot "schemas"
    New-Item -ItemType Directory -Force -Path $schemaDirectory | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $sidecarRoot "schemas") -Filter "*.schema.json" -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $schemaDirectory -Force }

    $configDirectory = Join-Path $versionRoot "config"
    New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
    $packageConfig = Read-Json $sidecarConfigPath
    $packageConfig.database.path = "data/aku-sidecar.db"
    $packageConfig.mediaProvenance.c2paToolPath = "c2patool.exe"
    $packageConfig.reasoning.providers.'codex-app-server'.executable = ""
    $packageConfig.bridge.trustedExtensionOrigins = @($extensionOrigin)
    $packageConfig.deployment = [ordered]@{
        mode = "production-installed-app"
        runtimeInstallKind = "installed"
        bridgeIdentityProfile = "production-app"
        releaseVersion = [string]$release.version
        sourceFreeze = ($sourceState.commits.Values -join ":")
        artifactId = $artifactName
    }
    Write-Utf8NoBom (Join-Path $configDirectory "sidecar.json") ($packageConfig | ConvertTo-Json -Depth 10)

    $bridgeVerificationText = & node (Join-Path $bridgeRoot "scripts\verify-extension-package.mjs")
    if ($LASTEXITCODE -ne 0) { throw "AkuBridge package verification failed." }
    $bridgeVerification = ($bridgeVerificationText | Out-String) | ConvertFrom-Json
    Assert-True ([string]$bridgeVerification.version -eq [string]$release.components.akuBridge.version) "Verified AkuBridge version differs from the release tuple."
    $bridgeOutput = Join-Path $versionRoot "AkuBridge"
    New-Item -ItemType Directory -Force -Path $bridgeOutput | Out-Null
    foreach ($file in @($bridgeVerification.files)) {
        Copy-VerifiedFile $bridgeRoot $bridgeOutput ([string]$file.path)
    }
    $projectionJson = & node (Join-Path $PSScriptRoot "project-bridge-package-identity.mjs") $bridgeIdentityRegistryPath $bridgeOutput "production-app"
    if ($LASTEXITCODE -ne 0) { throw "production-app Bridge identity projection failed." }
    $projection = ($projectionJson | Out-String) | ConvertFrom-Json
    Assert-True ([string]$projection.extensionId -eq $extensionId -and [string]$projection.extensionOrigin -eq $extensionOrigin) "Bridge identity projection returned the wrong production-app identity."
    Assert-NoReparsePoints $bridgeOutput "Staged Bridge"
    $stagedBridgeManifest = Read-Json (Join-Path $bridgeOutput "manifest.json")
    Assert-True ([string]$stagedBridgeManifest.key -eq [string]$identity.publicKey) "Projected Bridge manifest key differs from production-app identity."

    $chromiumOutput = Join-Path $versionRoot "chromium"
    Copy-Item -LiteralPath $ChromiumRoot -Destination $chromiumOutput -Recurse -Force
    Assert-NoReparsePoints $chromiumOutput "Staged Chromium"
    $stagedChromiumFiles = @(Get-ChildItem -LiteralPath $chromiumOutput -Recurse -File -Force)
    Assert-True ($stagedChromiumFiles.Count -eq $chromiumSourceFiles.Count) "Staged Chromium file count differs from the pinned source."
    foreach ($sourceFile in $chromiumSourceFiles) {
        $relative = Get-RelativeArtifactPath $ChromiumRoot $sourceFile.FullName
        $staged = Join-Path $chromiumOutput ($relative.Replace("/", [IO.Path]::DirectorySeparatorChar))
        Assert-True (Test-Path -LiteralPath $staged -PathType Leaf) "Staged Chromium file is missing: $relative"
        Assert-True ((Get-Item -LiteralPath $staged -Force).Length -eq $sourceFile.Length) "Staged Chromium file size differs: $relative"
        Assert-True ((Get-Sha256 $staged) -eq (Get-Sha256 $sourceFile.FullName)) "Staged Chromium file hash differs: $relative"
    }

    $payloadEntries = @(
        Get-ChildItem -LiteralPath $versionRoot -Recurse -File -Force |
            ForEach-Object {
                $relative = Get-RelativeArtifactPath $versionRoot $_.FullName
                Assert-PortableRelativePath $relative "Payload path"
                [ordered]@{
                    path = $relative
                    size = [int64]$_.Length
                    sha256 = Get-Sha256 $_.FullName
                }
            }
    )
    $payloadByPath = @{}
    foreach ($entry in $payloadEntries) {
        $payloadByPath[[string]$entry["path"]] = $entry
    }
    $sortedPayloadPaths = [string[]]$payloadByPath.Keys
    [Array]::Sort($sortedPayloadPaths, [StringComparer]::OrdinalIgnoreCase)
    $payload = @($sortedPayloadPaths | ForEach-Object { $payloadByPath[$_] })
    Assert-True ($payload.Count -gt 0) "Installed-app payload is empty."
    $payloadBytes = [int64]0
    foreach ($entry in $payload) {
        $payloadBytes += [int64]$entry["size"]
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        product = "AkuBrowser"
        platform = "windows-x64"
        version = [string]$release.version
        chromiumVersion = [string]$pin.version
        bridgeVersion = [string]$release.components.akuBridge.version
        bridgeContract = [string]$release.components.akuBridge.contractVersion
        sidecarPath = "AkuSidecar.exe"
        configPath = "config/sidecar.json"
        chromiumPath = $chromiumExecutableRelative
        bridgeExtensionPath = "AkuBridge"
        bridgeIdentity = [ordered]@{
            profile = "production-app"
            environment = [string]$identity.environment
            distribution = [string]$identity.distribution
            runtimeLifecycle = [string]$identity.runtimeLifecycle
            runtimeAcquisition = [string]$identity.runtimeAcquisition
            extensionId = $extensionId
            origin = $extensionOrigin
        }
        storage = [ordered]@{
            userDataRoot = "local-app-data"
            userDataRelativePath = "AkuBrowser/data"
            browserProfileRoot = "local-app-data"
            browserProfileRelativePath = "AkuBrowser/browser-profile"
        }
        health = [ordered]@{
            host = "127.0.0.1"
            port = 11122
            path = "/api/health"
            timeoutMs = 3000
        }
        payload = $payload
    }
    $versionManifestPath = Join-Path $versionRoot "manifest.json"
    Write-Utf8NoBom $versionManifestPath ($manifest | ConvertTo-Json -Depth 12)

    $stagedSidecarPath = Join-Path $versionRoot "AkuSidecar.exe"
    $stagedConfigPath = Join-Path $versionRoot "config\sidecar.json"
    $probeText = & $stagedSidecarPath `
        --config $stagedConfigPath `
        --bridge-extension-origin $extensionOrigin `
        --runtime-candidate-probe `
        --runtime-candidate-probe-schema 2 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Staged AkuSidecar candidate probe failed: $(($probeText | Out-String).Trim())"
    }
    try {
        $probe = ($probeText | Out-String) | ConvertFrom-Json
    }
    catch {
        throw "Staged AkuSidecar candidate probe returned invalid JSON: $(($probeText | Out-String).Trim())"
    }
    Assert-True ([string]$probe.status -eq "ok") "Staged AkuSidecar candidate probe is not ready."
    Assert-True ([string]$probe.version -eq [string]$release.version) "Staged AkuSidecar candidate version differs from the release tuple."
    Assert-True ([string]$probe.runtime -eq "go") "Staged AkuSidecar candidate runtime is unexpected."
    Assert-True ([string]$probe.bridgeContractVersion -eq [string]$release.components.akuBridge.contractVersion) "Staged AkuSidecar Bridge contract differs from the release tuple."
    Assert-True ([int]$probe.configVersion -eq 1) "Staged AkuSidecar config contract is unexpected."
    Assert-True ([int]$probe.databaseSchemaVersion -eq [int]$installedApp.database.currentSchemaVersion) "Staged AkuSidecar database schema differs from the installed-app contract."

    $runtimeDirectory = Join-Path $artifactRoot "runtime"
    New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
    $currentPointerPath = Join-Path $runtimeDirectory "current.json"
    $currentPointer = [ordered]@{
        schemaVersion = 1
        version = [string]$release.version
        manifestPath = "runtime/versions/$($release.version)/manifest.json"
    }
    Write-Utf8NoBom $currentPointerPath ($currentPointer | ConvertTo-Json -Depth 4)

    $launcherPath = Join-Path $artifactRoot "AkuBrowserLauncher.exe"
    $verifyOutput = & $launcherPath --verify-only --install-root $artifactRoot 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Staged AkuBrowserLauncher --verify-only failed: $(($verifyOutput | Out-String).Trim())"
    }

    $rootFiles = @($launcherPath, $currentPointerPath) | ForEach-Object {
        [ordered]@{
            path = Get-RelativeArtifactPath $artifactRoot $_
            size = [int64](Get-Item -LiteralPath $_).Length
            sha256 = Get-Sha256 $_
            source = if ($_ -eq $launcherPath) { "AkuBrowser/launcher" } else { "AkuBrowserLauncher activation pointer" }
        }
    }
    $installManifest = [ordered]@{
        schemaVersion = 1
        product = "AkuBrowser"
        version = [string]$release.version
        platform = "windows-x64"
        format = "installed-app-tuple"
        status = "staged-builder"
        signedInstaller = $false
        installerStatus = "not-shipped"
        sourceCommits = $sourceState.commits
        sourceDirty = @($sourceState.dirty)
        bridgeIdentity = [ordered]@{
            profile = "production-app"
            extensionId = $extensionId
            origin = $extensionOrigin
            authority = "config/bridge-identities.json"
        }
        chromium = [ordered]@{
            version = [string]$pin.version
            executable = $chromiumExecutableRelative
            fileCount = $chromiumSourceFiles.Count
            bytes = [int64](($chromiumSourceFiles | Measure-Object -Property Length -Sum).Sum)
            pinSha256 = Get-Sha256 $pinPath
            executableSha256 = $chromiumHash
        }
        database = $installedApp.database
        payload = [ordered]@{
            root = "runtime/versions/$($release.version)"
            fileCount = $payload.Count
            bytes = $payloadBytes
            manifest = "runtime/versions/$($release.version)/manifest.json"
        }
        rootFiles = $rootFiles
        provenance = [ordered]@{
            c2patool = [ordered]@{
                version = [string]$c2paPin.version
                sha256 = $c2paHash
                file = "runtime/versions/$($release.version)/c2patool.exe"
                licenses = @(
                    "runtime/versions/$($release.version)/third-party/c2patool/LICENSE-MIT",
                    "runtime/versions/$($release.version)/third-party/c2patool/LICENSE-APACHE",
                    "runtime/versions/$($release.version)/third-party/c2patool/THIRD-PARTY-NOTICE.md"
                )
            }
        }
    }
    Write-Utf8NoBom (Join-Path $artifactRoot "install-manifest.json") ($installManifest | ConvertTo-Json -Depth 12)

    [ordered]@{
        status = "ok"
        artifactPath = $artifactRoot
        version = [string]$release.version
        chromium = [ordered]@{
            version = [string]$pin.version
            files = $chromiumSourceFiles.Count
            bytes = [int64](($chromiumSourceFiles | Measure-Object -Property Length -Sum).Sum)
            sha256 = $chromiumHash
        }
        bridgeIdentity = [ordered]@{
            profile = "production-app"
            extensionId = $extensionId
            origin = $extensionOrigin
        }
        payload = [ordered]@{
            files = $payload.Count
            bytes = $payloadBytes
        }
        launcherSha256 = Get-Sha256 $launcherPath
        sidecarSha256 = Get-Sha256 (Join-Path $versionRoot "AkuSidecar.exe")
        sourceCommits = $sourceState.commits
        sourceDirty = @($sourceState.dirty)
    } | ConvertTo-Json -Depth 10
}
catch {
    if ($artifactCreated -and (Test-Path -LiteralPath $artifactRoot)) {
        Reset-ArtifactPath $artifactRoot $OutputRoot
    }
    throw
}
