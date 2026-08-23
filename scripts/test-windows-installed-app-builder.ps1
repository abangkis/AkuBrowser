[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ArtifactDirectory
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON file: $Path"
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-RelativePath([string] $Root, [string] $Path) {
    $rootUri = [Uri]((([IO.Path]::GetFullPath($Root)).TrimEnd([IO.Path]::DirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar)
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri([Uri][IO.Path]::GetFullPath($Path)).ToString()).Replace("\", "/")
}

function Assert-PortableRelativePath([string] $Path) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($Path)) "Payload path is empty."
    Assert-True (-not $Path.Contains("\") -and -not [IO.Path]::IsPathRooted($Path)) "Payload path is not portable: $Path"
    Assert-True (-not $Path.StartsWith("../") -and $Path -ne ".." -and $Path -ne ".") "Payload path escapes the version root: $Path"
    $normalized = [IO.Path]::GetFullPath((Join-Path "C:\" $Path)).Substring(3).Replace("\", "/")
    Assert-True ($normalized -eq $Path) "Payload path is not normalized: $Path"
}

function Assert-NoReparsePoints([string] $Root) {
    foreach ($entry in @(Get-ChildItem -LiteralPath $Root -Recurse -Force)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Artifact contains a reparse point: $($entry.FullName)"
        }
    }
}

Assert-True (Test-Path -LiteralPath $ArtifactDirectory -PathType Container) "Artifact directory was not found: $ArtifactDirectory"
$current = Read-Json (Join-Path $ArtifactDirectory "runtime\current.json")
$installManifest = Read-Json (Join-Path $ArtifactDirectory "install-manifest.json")
Assert-True ($current.schemaVersion -eq 1) "Active pointer schema is unexpected."
Assert-True ([string]$installManifest.status -eq "staged-builder" -and $installManifest.signedInstaller -eq $false) "Artifact claims a signed or shipped installer."
Assert-True ([string]$installManifest.bridgeIdentity.profile -eq "production-app") "Install provenance does not select production-app."
Assert-True ([int]$installManifest.database.currentSchemaVersion -gt 0 -and [string]$installManifest.database.rollbackStatus -eq "not-implemented") "Install provenance claims an invalid database contract."

$versionRoot = Join-Path $ArtifactDirectory (Join-Path "runtime\versions" ([string]$current.version))
$manifestPath = Join-Path $ArtifactDirectory ([string]$current.manifestPath).Replace("/", [IO.Path]::DirectorySeparatorChar)
Assert-True ([IO.Path]::GetFullPath($manifestPath) -eq [IO.Path]::GetFullPath((Join-Path $versionRoot "manifest.json"))) "Active pointer does not select the version manifest."
$manifest = Read-Json $manifestPath
Assert-True ($manifest.schemaVersion -eq 1 -and $manifest.product -eq "AkuBrowser" -and $manifest.platform -eq "windows-x64") "Bundle manifest identity is unexpected."
Assert-True ($manifest.version -eq $current.version) "Active pointer and bundle manifest versions differ."
Assert-True ($manifest.bridgeIdentity.profile -eq "production-app" -and $manifest.bridgeIdentity.distribution -eq "installed-app") "Bundle manifest Bridge identity is not production-app installed-app."
Assert-True ($manifest.bridgeIdentity.runtimeLifecycle -eq "managed" -and $manifest.bridgeIdentity.runtimeAcquisition -eq "bundled-installer") "Bundle manifest Bridge lifecycle metadata is unexpected."
Assert-True ($manifest.storage.userDataRoot -eq "local-app-data" -and $manifest.storage.browserProfileRoot -eq "local-app-data") "Bundle storage roots are not local-app-data."
Assert-True ($manifest.health.host -eq "127.0.0.1" -and $manifest.health.path -eq "/api/health" -and $manifest.health.timeoutMs -ge 1000) "Bundle health contract is not bounded loopback health."

foreach ($required in @(
    "AkuBrowserLauncher.exe",
    "runtime\current.json",
    "install-manifest.json",
    "runtime\versions\$($current.version)\AkuSidecar.exe",
    "runtime\versions\$($current.version)\AkuBridge\manifest.json",
    "runtime\versions\$($current.version)\chromium\pin.json",
    "runtime\versions\$($current.version)\chromium\bin\chrome.exe",
    "runtime\versions\$($current.version)\c2patool.exe",
    "runtime\versions\$($current.version)\config\sidecar.json"
)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $ArtifactDirectory $required) -PathType Leaf) "Artifact is missing $required"
}

$declared = @{}
$payloadBytes = [int64]0
$previousPath = ""
foreach ($file in @($manifest.payload)) {
    Assert-PortableRelativePath ([string]$file.path)
    Assert-True ([string]$file.path -cne "manifest.json") "Version manifest must not declare itself."
    Assert-True ([StringComparer]::OrdinalIgnoreCase.Compare([string]$file.path, $previousPath) -gt 0) "Payload entries are not deterministic and sorted: $($file.path)"
    $previousPath = [string]$file.path
    $key = ([string]$file.path).ToLowerInvariant()
    Assert-True (-not $declared.ContainsKey($key)) "Duplicate payload path: $($file.path)"
    $declared[$key] = $true
    $path = Join-Path $versionRoot ([string]$file.path).Replace("/", [IO.Path]::DirectorySeparatorChar)
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Declared payload file is missing: $($file.path)"
    $item = Get-Item -LiteralPath $path -Force
    Assert-True (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Declared payload is a reparse point: $($file.path)"
    Assert-True ([int64]$item.Length -eq [int64]$file.size) "Payload size mismatch: $($file.path)"
    Assert-True ((Get-Sha256 $path) -eq ([string]$file.sha256).ToLowerInvariant()) "Payload hash mismatch: $($file.path)"
    $payloadBytes += [int64]$file.size
}

Assert-NoReparsePoints $versionRoot
$actualPayload = @(Get-ChildItem -LiteralPath $versionRoot -Recurse -File -Force | ForEach-Object {
    $relative = Get-RelativePath $versionRoot $_.FullName
    if ($relative -ne "manifest.json") { $relative }
}) | Sort-Object
Assert-True ($actualPayload.Count -eq $declared.Count) "Payload declaration count differs from version-root regular files."
foreach ($path in $actualPayload) {
    Assert-True ($declared.ContainsKey($path.ToLowerInvariant())) "Undeclared version-root file: $path"
}

$pin = Read-Json (Join-Path $versionRoot "chromium\pin.json")
Assert-True ([string]$pin.executable.Replace("\", "/") -eq "bin/chrome.exe") "Staged Chromium pin points outside bin/chrome.exe."
Assert-True ((Get-Sha256 (Join-Path $versionRoot "chromium\bin\chrome.exe")) -eq ([string]$pin.executableSha256).ToLowerInvariant()) "Staged Chromium executable does not match pin.json."
$config = Read-Json (Join-Path $versionRoot "config\sidecar.json")
Assert-True (@($config.bridge.trustedExtensionOrigins).Count -eq 1 -and [string]$config.bridge.trustedExtensionOrigins[0] -eq [string]$manifest.bridgeIdentity.origin) "Sidecar config does not trust exactly the manifest Bridge origin."
Assert-True ($config.deployment.mode -eq "production-installed-app" -and $config.deployment.runtimeInstallKind -eq "installed" -and $config.deployment.bridgeIdentityProfile -eq "production-app") "Sidecar config does not record installed-app production metadata."

$probeText = & (Join-Path $versionRoot "AkuSidecar.exe") `
    --config (Join-Path $versionRoot "config\sidecar.json") `
    --bridge-extension-origin ([string]$manifest.bridgeIdentity.origin) `
    --runtime-candidate-probe `
    --runtime-candidate-probe-schema 2 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Staged Sidecar candidate probe failed: $(($probeText | Out-String).Trim())"
$probe = ($probeText | Out-String) | ConvertFrom-Json
Assert-True ($probe.status -eq "ok" -and $probe.version -eq $manifest.version -and $probe.runtime -eq "go") "Staged Sidecar candidate probe identity is unexpected."
Assert-True ($probe.bridgeContractVersion -eq $manifest.bridgeContract -and [int]$probe.configVersion -eq 1) "Staged Sidecar candidate probe contract differs from the tuple."
Assert-True ([int]$probe.databaseSchemaVersion -eq [int]$installManifest.database.currentSchemaVersion) "Staged Sidecar database schema differs from install provenance."

$identityCheck = & node (Join-Path $browserRoot "scripts\bridge-extension-identity.mjs") (Join-Path $browserRoot "config\bridge-identities.json") (Join-Path $versionRoot "AkuBridge\manifest.json") "production-app"
Assert-True ($LASTEXITCODE -eq 0) "Staged Bridge identity projection could not be independently verified."
$identity = ($identityCheck | Out-String) | ConvertFrom-Json
Assert-True ([string]$identity.extensionOrigin -eq [string]$manifest.bridgeIdentity.origin -and [string]$identity.extensionId -eq [string]$manifest.bridgeIdentity.extensionId) "Staged Bridge identity differs from bundle manifest."

[ordered]@{
    status = "ok"
    artifactPath = $ArtifactDirectory
    version = [string]$manifest.version
    payloadFiles = $declared.Count
    payloadBytes = $payloadBytes
    bridgeIdentity = [string]$manifest.bridgeIdentity.extensionId
    chromiumVersion = [string]$manifest.chromiumVersion
} | ConvertTo-Json -Depth 6
