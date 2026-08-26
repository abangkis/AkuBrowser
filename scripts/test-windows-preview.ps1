[CmdletBinding()]
param(
    [string] $ArtifactDirectory = "",
    [string] $ZipPath = ""
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$release = Get-Content -LiteralPath (Join-Path $browserRoot "release\release-manifest.json") -Raw | ConvertFrom-Json
$bridgeIdentityRegistry = Get-Content -LiteralPath (Join-Path $browserRoot "config\bridge-identities.json") -Raw | ConvertFrom-Json
$bridgeIdentityProfile = [string]$release.distribution.offlineBundle.bridgeIdentityProfile
$bridgeIdentityProperty = $bridgeIdentityRegistry.profiles.PSObject.Properties[$bridgeIdentityProfile]
if ($bridgeIdentityRegistry.schemaVersion -ne 2 -or [string]::IsNullOrWhiteSpace($bridgeIdentityProfile) -or $null -eq $bridgeIdentityProperty) {
    throw "The release does not select a valid Bridge identity profile."
}
$bridgeIdentity = $bridgeIdentityProperty.Value
$bridgeExtensionOrigin = "chrome-extension://$([string]$bridgeIdentity.extensionId)/"

function Resolve-SharedTemporaryRoot {
    $ancestor = [IO.DirectoryInfo]$workspaceRoot
    while ($null -ne $ancestor) {
        $candidate = Join-Path $ancestor.FullName "SharedTemp"
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $root = [IO.Path]::GetFullPath((Join-Path $candidate "AkuBrowser\preview-validation"))
            New-Item -ItemType Directory -Force -Path $root | Out-Null
            return $root
        }
        $ancestor = $ancestor.Parent
    }
    throw "No ancestor-owned SharedTemp exists above $workspaceRoot"
}

$temporaryRoot = Resolve-SharedTemporaryRoot
$temporaryPrefix = $temporaryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$browserPrefix = [IO.Path]::GetFullPath($browserRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

function Remove-TemporaryDirectory([string] $Path) {
    $absolutePath = [IO.Path]::GetFullPath($Path)
    if (-not $absolutePath.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the shared temporary root: $absolutePath"
    }
    if (-not (Test-Path -LiteralPath $absolutePath)) {
        return
    }

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            Remove-Item -LiteralPath $absolutePath -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -eq 10) {
                Write-Warning "Preview validation passed, but temporary cleanup remains deferred because another process still holds a file: $absolutePath"
                return
            }
            Start-Sleep -Milliseconds 300
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
    if ([string]::IsNullOrWhiteSpace($ZipPath)) {
        $ZipPath = Join-Path $browserRoot "artifacts\AkuBrowser-$($release.version)-windows-x64.zip"
    }
    $ZipPath = [IO.Path]::GetFullPath($ZipPath)
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Preview ZIP was not found: $ZipPath"
    }
    $extractionRoot = Join-Path $temporaryRoot ("akubrowser-release-extract-" + [Guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Force -Path $extractionRoot | Out-Null
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractionRoot
        & $PSCommandPath -ArtifactDirectory $extractionRoot
    }
    finally {
        Remove-TemporaryDirectory -Path $extractionRoot
    }
    exit 0
}
$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
$artifactPrefix = $ArtifactDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $artifactPrefix.StartsWith($browserPrefix, [StringComparison]::OrdinalIgnoreCase) -and
    -not $artifactPrefix.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Preview validation may execute artifacts only from the AkuBrowser project or ancestor-owned SharedTemp: $ArtifactDirectory"
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function ConvertTo-NativeArgument([string] $Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

foreach ($required in @(
    "AkuSidecar.exe",
    "c2patool.exe",
    "third-party\c2patool\LICENSE-MIT",
    "third-party\c2patool\LICENSE-APACHE",
    "third-party\c2patool\THIRD-PARTY-NOTICE.md",
    "AkuBridge\manifest.json",
    "config\sidecar.json",
    "schemas\acquisition-plan.schema.json",
    "schemas\ai-deep-detection.schema.json",
    "schemas\calibration-label.schema.json",
    "schemas\calibration-profile-snapshot.schema.json",
    "schemas\calibration-session.schema.json",
    "schemas\reasoning-result.schema.json",
    "schemas\semantic-event-resolution.schema.json",
    "release-manifest.json",
    "artifact-manifest.json",
    "checksums.sha256",
    "Start-AkuBrowser.ps1",
    "Start-AkuBrowser.cmd",
    "README.md"
)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $ArtifactDirectory $required) -PathType Leaf) "Artifact is missing $required"
}

$bundleReadme = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "README.md") -Raw
$bridgeInstallInstruction = $bundleReadme.IndexOf('Load unpacked', [StringComparison]::OrdinalIgnoreCase)
$primaryLauncherInstruction = $bundleReadme.IndexOf('.\Start-AkuBrowser.ps1', [StringComparison]::OrdinalIgnoreCase)
$fallbackLauncherInstruction = $bundleReadme.IndexOf('use `Start-AkuBrowser.cmd` as', [StringComparison]::OrdinalIgnoreCase)
Assert-True ($bridgeInstallInstruction -ge 0) "Bundle README does not explain how to load its offline AkuBridge package."
Assert-True ($primaryLauncherInstruction -ge 0) "Bundle README does not identify Start-AkuBrowser.ps1 as the primary launcher."
Assert-True ($fallbackLauncherInstruction -ge 0) "Bundle README does not identify Start-AkuBrowser.cmd as the fallback launcher."
Assert-True ($bundleReadme.IndexOf('exception for that exact file', [StringComparison]::OrdinalIgnoreCase) -ge 0) "Bundle README does not explain the narrow AkuSidecar.exe antivirus exception."
Assert-True ($bridgeInstallInstruction -lt $primaryLauncherInstruction) "Bundle README must install AkuBridge before starting AkuBrowser."
Assert-True ($primaryLauncherInstruction -lt $fallbackLauncherInstruction) "Bundle README must present the PowerShell launcher before the CMD fallback."

$checksumLines = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "checksums.sha256")
foreach ($line in $checksumLines) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
        throw "Invalid checksum line: $line"
    }
    $expected = $Matches[1]
    $relative = $Matches[2].Replace("/", [IO.Path]::DirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $ArtifactDirectory $relative))
    $prefix = $ArtifactDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Assert-True ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Checksum path escapes the artifact: $relative"
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Checksummed file is missing: $relative"
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-True ($actual -eq $expected) "Checksum mismatch: $relative"
}

$artifactRelease = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "release-manifest.json") -Raw | ConvertFrom-Json
$artifactManifest = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "artifact-manifest.json") -Raw | ConvertFrom-Json
$bridgeManifest = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "AkuBridge\manifest.json") -Raw | ConvertFrom-Json
$packageConfig = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "config\sidecar.json") -Raw | ConvertFrom-Json
Assert-True ($artifactRelease.version -eq $release.version) "Artifact release version differs from AkuBrowser."
Assert-True ($bridgeManifest.version_name -eq $release.components.akuBridge.version) "Bundled AkuBridge product version differs from the release tuple."
Assert-True ($bridgeManifest.version -eq $release.components.akuBridge.chromeVersion) "Bundled AkuBridge Chrome version differs from the release tuple."
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$bridgeManifest.key)) "Offline AkuBridge must retain its stable manifest public key."
Assert-True ($bridgeIdentity.distribution -eq "offline-bundle") "The release Bridge identity is not an offline production profile."
Assert-True ($packageConfig.deployment.mode -eq "production-offline") "Packaged AkuSidecar does not declare offline production mode."
Assert-True ($packageConfig.deployment.runtimeInstallKind -eq "portable") "Packaged AkuSidecar does not declare portable runtime ownership."
Assert-True ($packageConfig.deployment.bridgeIdentityProfile -eq $bridgeIdentityProfile) "Packaged AkuSidecar records the wrong Bridge identity profile."
Assert-True ($null -ne $packageConfig.reasoning.providers.'codex-app-server') "Packaged AkuSidecar is missing the codex-app-server provider configuration."
Assert-True ([string]$packageConfig.reasoning.providers.'codex-app-server'.executable -eq "") "Packaged AkuSidecar must discover the Codex executable at runtime."
Assert-True (@($packageConfig.bridge.trustedExtensionOrigins).Count -eq 1 -and $packageConfig.bridge.trustedExtensionOrigins[0] -eq $bridgeExtensionOrigin) "Packaged AkuSidecar does not trust exactly the release-selected Bridge origin."
Assert-True ($artifactManifest.bridgeIdentity.profile -eq $bridgeIdentityProfile) "Artifact provenance records the wrong Bridge identity profile."
Assert-True ($artifactManifest.bridgeIdentity.distribution -eq $bridgeIdentity.distribution) "Artifact provenance records the wrong Bridge distribution."
Assert-True ($artifactManifest.bridgeIdentity.authority -eq "config/bridge-identities.json") "Artifact provenance does not record the Bridge identity authority."
Assert-True ($artifactManifest.bridgeIdentity.extensionOrigin -eq $bridgeExtensionOrigin) "Artifact provenance records the wrong Bridge extension origin."
$c2paToolPath = Join-Path $ArtifactDirectory "c2patool.exe"
$c2paToolHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $c2paToolPath).Hash.ToLowerInvariant()
Assert-True ($c2paToolHash -eq $artifactRelease.components.c2paTool.sha256) "Bundled c2patool SHA-256 differs from the release pin."
Assert-True ($artifactManifest.bundledTools.c2paTool.sha256 -eq $c2paToolHash) "Artifact provenance does not record the bundled c2patool hash."
Assert-True ($artifactManifest.bundledTools.c2paTool.workspaceSource -eq $artifactRelease.components.c2paTool.workspaceSource) "Artifact provenance does not record the pinned c2patool workspace source."
Assert-True (@($artifactManifest.bundledTools.c2paTool.licenses).Count -eq 3) "Artifact provenance does not record all c2patool license files."
$c2paMIT = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "third-party\c2patool\LICENSE-MIT") -Raw
$c2paApache = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "third-party\c2patool\LICENSE-APACHE") -Raw
$c2paNotice = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "third-party\c2patool\THIRD-PARTY-NOTICE.md") -Raw
Assert-True ($c2paMIT.Contains("© Copyright 2020 Adobe. All rights reserved.")) "Bundled c2patool MIT license is not the upstream 0.26.60 text."
Assert-True ($c2paApache.Contains("Copyright 2020 Adobe")) "Bundled c2patool Apache license is not the upstream 0.26.60 text."
Assert-True ($c2paNotice.Contains("c2patool-v0.26.60")) "Bundled c2patool notice does not identify the pinned upstream release."
$c2paMITHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $ArtifactDirectory "third-party\c2patool\LICENSE-MIT")).Hash.ToLowerInvariant()
$c2paApacheHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $ArtifactDirectory "third-party\c2patool\LICENSE-APACHE")).Hash.ToLowerInvariant()
Assert-True ($c2paMITHash -eq $artifactRelease.components.c2paTool.licenseSha256.mit) "Bundled c2patool MIT license differs byte-for-byte from upstream 0.26.60."
Assert-True ($c2paApacheHash -eq $artifactRelease.components.c2paTool.licenseSha256.apache2) "Bundled c2patool Apache license differs byte-for-byte from upstream 0.26.60."
$c2paToolVersion = (& $c2paToolPath --version | Out-String).Trim()
Assert-True ($LASTEXITCODE -eq 0) "Bundled c2patool could not report its version."
Assert-True ($c2paToolVersion -eq "c2patool $($artifactRelease.components.c2paTool.version)") "Bundled c2patool version differs from the release pin."

$savedPath = $env:PATH
try {
    $env:PATH = "$env:SystemRoot\System32"
    $codexProbeText = & (Join-Path $ArtifactDirectory "AkuSidecar.exe") --discover-codex
    $codexProbeExit = $LASTEXITCODE
}
finally {
    $env:PATH = $savedPath
}
$codexProbe = ($codexProbeText | Out-String) | ConvertFrom-Json
Assert-True ($codexProbeExit -eq 0) "Packaged AkuSidecar could not discover Codex with PATH restricted."
Assert-True ($codexProbe.status -eq "ok") "Packaged Codex discovery did not return an ok status."
Assert-True (-not [string]::IsNullOrWhiteSpace($codexProbe.executable)) "Packaged Codex discovery returned no executable."
Assert-True (-not [string]::IsNullOrWhiteSpace($codexProbe.version)) "Packaged Codex discovery returned no version."

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$smokeRoot = Join-Path $temporaryRoot ("akubrowser-release-smoke-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
$database = Join-Path $smokeRoot "aku-sidecar.db"
$process = $null
try {
    $arguments = @(
        "--config", (Join-Path $ArtifactDirectory "config\sidecar.json"),
        "--database", $database,
        "--port", [string]$port
    ) | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $ArtifactDirectory "AkuSidecar.exe"
    $startInfo.Arguments = $arguments -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    Assert-True $process.Start() "Packaged AkuSidecar process could not be started."

    $health = $null
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        if ($process.HasExited) {
            $errorText = $process.StandardError.ReadToEnd()
            throw "Packaged AkuSidecar exited during startup: $errorText"
        }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/health" -TimeoutSec 1
            if ($health.status -eq "ok") { break }
        }
        catch {}
        Start-Sleep -Milliseconds 125
    }
    Assert-True ($null -ne $health -and $health.status -eq "ok") "Packaged AkuSidecar did not become healthy."
    Assert-True ($health.version -eq $release.components.akuSidecar.version) "Packaged AkuSidecar reports the wrong version."
    Assert-True ($health.runtime -eq "go") "Packaged AkuSidecar does not report the Go runtime."
    Assert-True ($health.provider -eq "codex-app-server") "Packaged AkuSidecar did not initialize the release reasoning provider."
    Assert-True ($health.mediaProvenanceRuntime.available -eq $true) "Packaged AkuSidecar did not discover the adjacent c2patool runtime."
    Assert-True ($health.mediaProvenanceRuntime.provider -eq "c2patool") "Packaged AkuSidecar reports the wrong media-provenance provider."

    $bootstrap = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/bootstrap" -TimeoutSec 5
    Assert-True ($bootstrap.settings.loadProfile -eq "standard") "Packaged fresh database does not use Standard 1x."
    Assert-True ($bootstrap.settings.aiDetectionPresentation -eq "drawer") "Packaged fresh database does not default AI Signals to Drawer."
    Assert-True ($bootstrap.settings.autoUpdateDailyTokenBudget -eq 2000000) "Packaged fresh database does not default the daily model budget to 2M tokens."
    Assert-True ($bootstrap.settings.reasoningEvaluationProfile -eq "luna_high") "Packaged fresh database does not default evaluation to Luna High."

    $ui = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/" -TimeoutSec 5
    Assert-True ($ui.StatusCode -eq 200 -and $ui.Content -match "AkuBrowser") "Embedded AkuBrowser UI was not delivered."

    [ordered]@{
        status = "ok"
        version = $health.version
        runtime = $health.runtime
        provider = $health.provider
        port = $port
        checksumFiles = @($checksumLines).Count
        defaultLoadProfile = $bootstrap.settings.loadProfile
        defaultAIPresentation = $bootstrap.settings.aiDetectionPresentation
        defaultEvaluationProfile = $bootstrap.settings.reasoningEvaluationProfile
        codexDiscoverySource = $codexProbe.source
        codexVersion = $codexProbe.version
        c2paToolVersion = $artifactRelease.components.c2paTool.version
        c2paToolSha256 = $c2paToolHash
    } | ConvertTo-Json
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
    }
    Remove-TemporaryDirectory -Path $smokeRoot
}
