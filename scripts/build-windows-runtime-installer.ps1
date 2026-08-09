[CmdletBinding()]
param(
    [string] $BridgeIdentityProfile = "",
    [string] $OutputRoot = "",
    [string] $C2paToolPath = "",
    [string] $CertificatePath = "",
    [string] $CertificatePassword = "",
    [string] $SigningThumbprint = "",
    [string] $UpdatePublicKey = "",
    [string] $UpdateSigningPrivateKeyPath = "",
    [string] $TimestampUrl = "http://timestamp.digicert.com",
    [string] $NsisPath = "",
    [switch] $UnsignedLocalCandidate,
    [switch] $UnsignedStableCandidate,
    [switch] $SkipValidation,
    [switch] $AllowDirty
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$bridgeRoot = Join-Path $workspaceRoot "AkuBridge"
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
$installerSource = Join-Path $browserRoot "installer\windows"
$releaseManifestPath = Join-Path $browserRoot "release\release-manifest.json"
$bridgeIdentityRegistryPath = Join-Path $browserRoot "config\bridge-identities.json"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-RelativePath([string] $BasePath, [string] $Path) {
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $baseUri = [Uri]($base + [IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri][IO.Path]::GetFullPath($Path)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

function Reset-Path([string] $Path, [string] $AllowedRoot, [switch] $Directory) {
    $absolutePath = [IO.Path]::GetFullPath($Path)
    $absoluteRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $prefix = $absoluteRoot + [IO.Path]::DirectorySeparatorChar
    Assert-True ($absolutePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Refusing to replace a path outside the installer artifact root: $absolutePath"
    if (Test-Path -LiteralPath $absolutePath) {
        Remove-Item -LiteralPath $absolutePath -Recurse -Force
    }
    if ($Directory) {
        New-Item -ItemType Directory -Force -Path $absolutePath | Out-Null
    }
}

function Invoke-Git([string] $Repository, [string[]] $Arguments) {
    $value = & git -C $Repository @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Repository"
    }
    return ($value | Out-String).Trim()
}

function Find-SignTool {
    $roots = @(
        "C:\Program Files (x86)\Windows Kits\10\bin",
        "C:\Program Files\Windows Kits\10\bin"
    )
    $candidates = foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Recurse -Filter "signtool.exe" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -eq "x64" }
        }
    }
    $selected = $candidates | Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $selected) {
        throw "SignTool was not found in the Windows SDK."
    }
    return $selected.FullName
}

function Find-NsisCompiler([string] $RequestedPath) {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates += $RequestedPath
    }
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $candidates += $command.Source
    }
    $candidates += @(
        "C:\Program Files (x86)\NSIS\makensis.exe",
        "C:\Program Files\NSIS\makensis.exe"
    )
    $selected = $candidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($selected)) {
        throw "NSIS 3 compiler was not found. Install NSIS or pass -NsisPath."
    }
    return [IO.Path]::GetFullPath($selected)
}

function Sign-Binary([string] $Path, [string] $SignTool) {
    $arguments = @(
        "sign",
        "/fd", "SHA256",
        "/tr", $TimestampUrl,
        "/td", "SHA256",
        "/d", "AkuBrowser Runtime",
        "/du", "https://github.com/abangkis/AkuBrowser"
    )
    if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
        $arguments += @("/f", [IO.Path]::GetFullPath($CertificatePath))
        if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
            $arguments += @("/p", $CertificatePassword)
        }
    }
    else {
        $arguments += @("/sha1", $SigningThumbprint)
    }
    $arguments += $Path
    & $SignTool @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode signing failed for $([IO.Path]::GetFileName($Path))."
    }
    & $SignTool verify /pa /all $Path | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode verification failed for $([IO.Path]::GetFileName($Path))."
    }
}

$release = Read-Json $releaseManifestPath
$bridgeIdentityRegistry = Read-Json $bridgeIdentityRegistryPath
Assert-True ([string]$release.version -match '^\d+\.\d+\.\d+$') "The installer requires a three-part numeric release version."
Assert-True (-not ($UnsignedLocalCandidate -and $UnsignedStableCandidate)) "Choose only one unsigned installer mode."
if ($UnsignedStableCandidate) {
    Assert-True ($release.channel -eq "stable") "Unsigned stable installers require a stable release manifest channel."
    Assert-True ($release.distribution.chromeStore.nativeRuntimeInstallers.'windows-x64'.trustState -eq "unsigned") "The stable Windows installer trust state must be declared unsigned."
}
$versionQuad = "$($release.version).0"
$nsisCompiler = Find-NsisCompiler $NsisPath
$releaseBridgeIdentityProfile = [string]$release.distribution.chromeStore.bridgeIdentityProfile
Assert-True ($bridgeIdentityRegistry.schemaVersion -eq 1) "Unsupported Bridge identity registry schema."
$releaseBridgeIdentityProperty = $bridgeIdentityRegistry.profiles.PSObject.Properties[$releaseBridgeIdentityProfile]
Assert-True (-not [string]::IsNullOrWhiteSpace($releaseBridgeIdentityProfile) -and $null -ne $releaseBridgeIdentityProperty) "The release manifest must select an existing Bridge identity profile."
$releaseBridgeIdentity = $releaseBridgeIdentityProperty.Value
$releaseExtensionId = [string]$releaseBridgeIdentity.extensionId
Assert-True ($releaseBridgeIdentity.distribution -eq "chrome-web-store") "The production Bridge identity must use Chrome Web Store distribution."
Assert-True ($releaseExtensionId -match '^[a-p]{32}$') "The production Bridge identity must declare an exact Chrome Web Store extension ID."
if ([string]::IsNullOrWhiteSpace($BridgeIdentityProfile)) {
    $BridgeIdentityProfile = $releaseBridgeIdentityProfile
}
$selectedBridgeIdentityProperty = $bridgeIdentityRegistry.profiles.PSObject.Properties[$BridgeIdentityProfile]
Assert-True ($null -ne $selectedBridgeIdentityProperty) "BridgeIdentityProfile must select an identity declared in config/bridge-identities.json."
$selectedBridgeIdentity = $selectedBridgeIdentityProperty.Value
$selectedBridgeIdentityDistribution = [string]$selectedBridgeIdentity.distribution
$ExtensionId = [string]$selectedBridgeIdentity.extensionId
Assert-True ($ExtensionId -match '^[a-p]{32}$') "The selected Bridge identity must declare an exact 32-character Chrome extension ID."
Assert-True (-not ($CertificatePath -and $SigningThumbprint)) "Choose a PFX path or certificate thumbprint, not both."
if (-not $UnsignedLocalCandidate) {
    Assert-True ($BridgeIdentityProfile -eq $releaseBridgeIdentityProfile) "Production installers must use the Bridge identity profile selected by the release manifest."
    Assert-True ($selectedBridgeIdentityDistribution -eq "chrome-web-store") "Production installers must use a Chrome Web Store Bridge identity."
    $placeholderIds = @(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "abcdefghijklmnopabcdefghijklmnop"
    )
    Assert-True ($placeholderIds -notcontains $ExtensionId) "Production installer builds reject placeholder extension IDs."
    Assert-True ($ExtensionId -notmatch '^([a-p])\1{31}$') "Production installer builds reject repeated-character placeholder extension IDs."
    if (-not $UnsignedStableCandidate) {
        Assert-True ($CertificatePath -or $SigningThumbprint) "Production installer builds require an Authenticode signing certificate."
        Assert-True (-not [string]::IsNullOrWhiteSpace($TimestampUrl)) "Production installer builds require an RFC 3161 timestamp URL."
        Assert-True (-not [string]::IsNullOrWhiteSpace($UpdatePublicKey)) "Production installer builds require the pinned runtime-update public key."
        Assert-True (-not [string]::IsNullOrWhiteSpace($UpdateSigningPrivateKeyPath)) "Production installer builds require the runtime-update signing key path."
    }
}
if ($CertificatePath) {
    $CertificatePath = [IO.Path]::GetFullPath($CertificatePath)
    Assert-True (Test-Path -LiteralPath $CertificatePath -PathType Leaf) "The signing certificate was not found."
}
if (-not [string]::IsNullOrWhiteSpace($UpdatePublicKey)) {
    try {
        $decodedUpdatePublicKey = [Convert]::FromBase64String($UpdatePublicKey)
    }
    catch {
        throw "UpdatePublicKey must be valid base64."
    }
    Assert-True ($decodedUpdatePublicKey.Length -eq 32) "UpdatePublicKey must contain an Ed25519 32-byte public key."
}
if (-not [string]::IsNullOrWhiteSpace($UpdateSigningPrivateKeyPath)) {
    $UpdateSigningPrivateKeyPath = [IO.Path]::GetFullPath($UpdateSigningPrivateKeyPath)
    Assert-True (Test-Path -LiteralPath $UpdateSigningPrivateKeyPath -PathType Leaf) "The runtime-update signing key was not found."
}
if ([string]::IsNullOrWhiteSpace($CertificatePassword) -and -not [string]::IsNullOrWhiteSpace($env:AKU_WINDOWS_SIGNING_PASSWORD)) {
    $CertificatePassword = $env:AKU_WINDOWS_SIGNING_PASSWORD
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $browserRoot "artifacts\runtime-installer"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($C2paToolPath)) {
    $C2paToolPath = Join-Path $sidecarRoot "runtime\dev\c2patool.exe"
}
$C2paToolPath = [IO.Path]::GetFullPath($C2paToolPath)
Assert-True (Test-Path -LiteralPath $C2paToolPath -PathType Leaf) "The pinned c2patool binary was not found: $C2paToolPath"

$bridgePackage = Read-Json (Join-Path $bridgeRoot "package.json")
$bridgeManifest = Read-Json (Join-Path $bridgeRoot "manifest.json")
$sidecarDomain = Get-Content -LiteralPath (Join-Path $sidecarRoot "internal\domain\types.go") -Raw
Assert-True ($release.distribution.authorityRepository -eq "AkuBrowser") "AkuBrowser is not the distribution authority."
Assert-True ($release.components.akuBridge.version -eq $bridgePackage.version) "AkuBridge version differs from the release tuple."
Assert-True ($release.components.akuBridge.chromeVersion -eq $bridgeManifest.version) "AkuBridge Chrome version differs from the release tuple."
Assert-True ($sidecarDomain -match ('ApplicationVersion\s*=\s*"' + [regex]::Escape($release.components.akuSidecar.version) + '"')) "AkuSidecar version differs from the release tuple."

$c2paSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $C2paToolPath).Hash.ToLowerInvariant()
Assert-True ($c2paSourceHash -eq $release.components.c2paTool.sha256) "The source c2patool SHA-256 differs from the pinned release manifest."
$c2paVersion = (& $C2paToolPath --version | Out-String).Trim()
Assert-True ($LASTEXITCODE -eq 0) "c2patool could not report its version."
Assert-True ($c2paVersion -eq "c2patool $($release.components.c2paTool.version)") "c2patool version differs from the release tuple."

$repositories = [ordered]@{
    akuBrowser = $browserRoot
    akuBridge = $bridgeRoot
    akuSidecar = $sidecarRoot
}
$sourceCommits = [ordered]@{}
$dirty = @()
foreach ($entry in $repositories.GetEnumerator()) {
    $sourceCommits[$entry.Key] = Invoke-Git $entry.Value @("rev-parse", "HEAD")
    if (-not [string]::IsNullOrWhiteSpace((Invoke-Git $entry.Value @("status", "--porcelain")))) {
        $dirty += $entry.Key
    }
}
if ($dirty.Count -gt 0 -and -not $AllowDirty) {
    throw "Runtime installer sources must be clean. Dirty repositories: $($dirty -join ', ')."
}

if (-not $SkipValidation) {
    & (Join-Path $PSScriptRoot "check.ps1") -DistributionOnly
    if ($LASTEXITCODE -ne 0) {
        throw "Distribution validation failed."
    }
    Push-Location (Join-Path $bridgeRoot "native-host")
    try {
        & go test -count=1 ./...
        if ($LASTEXITCODE -ne 0) { throw "Native host tests failed." }
    }
    finally { Pop-Location }
    Push-Location $installerSource
    try {
        & go test -count=1 ./...
        if ($LASTEXITCODE -ne 0) { throw "Windows installer tests failed." }
    }
    finally { Pop-Location }
}

$suffix = if ($UnsignedLocalCandidate) { "-unsigned-local" } else { "" }
$artifactName = "AkuBrowserRuntimeSetup-$($release.version)$suffix.exe"
$artifactPath = Join-Path $OutputRoot $artifactName
$checksumPath = "$artifactPath.sha256"
$buildRoot = Join-Path $OutputRoot ".runtime-installer-build"
Reset-Path $buildRoot $OutputRoot -Directory
Reset-Path $artifactPath $OutputRoot
Reset-Path $checksumPath $OutputRoot

$payloadRoot = Join-Path $buildRoot "payload"
$hostPayload = Join-Path $payloadRoot "host"
$runtimePayload = Join-Path $payloadRoot "runtime\versions\$($release.version)"
New-Item -ItemType Directory -Force -Path $hostPayload | Out-Null
New-Item -ItemType Directory -Force -Path $runtimePayload | Out-Null

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

    Push-Location (Join-Path $bridgeRoot "native-host")
    try {
        $hostLdflags = "-s -w"
        if (-not [string]::IsNullOrWhiteSpace($UpdatePublicKey)) {
            $hostLdflags += " -X main.pinnedUpdatePublicKey=$UpdatePublicKey"
        }
        & go build -trimpath -ldflags $hostLdflags -o (Join-Path $hostPayload "AkuBrowserRuntimeHost.exe") .
        if ($LASTEXITCODE -ne 0) { throw "AkuBrowser Runtime Host build failed." }
    }
    finally { Pop-Location }

    Push-Location $sidecarRoot
    try {
        & go build -trimpath -ldflags "-s -w" -o (Join-Path $runtimePayload "AkuSidecar.exe") .\cmd\akusidecar
        if ($LASTEXITCODE -ne 0) { throw "AkuSidecar installer build failed." }
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

Copy-Item -LiteralPath $C2paToolPath -Destination (Join-Path $runtimePayload "c2patool.exe")
$configOutput = Join-Path $runtimePayload "config"
New-Item -ItemType Directory -Force -Path $configOutput | Out-Null
$config = Read-Json (Join-Path $sidecarRoot "config\sidecar.json")
$config.database.path = "runtime/aku-browser.db"
$config.reasoning.executable = ""
$config.bridge.trustedExtensionOrigins = @("chrome-extension://$ExtensionId/")
Write-Utf8NoBom (Join-Path $configOutput "sidecar.json") ($config | ConvertTo-Json -Depth 10)

$schemasOutput = Join-Path $runtimePayload "schemas"
New-Item -ItemType Directory -Force -Path $schemasOutput | Out-Null
Get-ChildItem -LiteralPath (Join-Path $sidecarRoot "schemas") -Filter "*.schema.json" -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $schemasOutput }

$licenseOutput = Join-Path $runtimePayload "third-party\c2patool"
New-Item -ItemType Directory -Force -Path $licenseOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $browserRoot "release\third-party\c2patool\LICENSE-MIT") -Destination $licenseOutput
Copy-Item -LiteralPath (Join-Path $browserRoot "release\third-party\c2patool\THIRD-PARTY-NOTICE.md") -Destination $licenseOutput

$hostManifest = [ordered]@{
    name = "com.akubrowser.runtime"
    description = "AkuBrowser Runtime Host"
    path = "AkuBrowserRuntimeHost.exe"
    type = "stdio"
    allowed_origins = @("chrome-extension://$ExtensionId/")
}
Write-Utf8NoBom (Join-Path $hostPayload "com.akubrowser.runtime.json") ($hostManifest | ConvertTo-Json -Depth 5)

$currentOutput = Join-Path $payloadRoot "runtime"
New-Item -ItemType Directory -Force -Path $currentOutput | Out-Null
$current = [ordered]@{
    schemaVersion = 1
    channel = if ($UnsignedLocalCandidate) { $release.channel } else { "stable" }
    version = $release.version
    runtimeRevision = $release.components.akuBridge.runtimeRevision
    bridgeContractVersion = $release.components.akuBridge.contractVersion
    rollbackVersion = $null
}
Write-Utf8NoBom (Join-Path $currentOutput "current.json") ($current | ConvertTo-Json -Depth 5)

$signTool = $null
if (-not $UnsignedLocalCandidate -and -not $UnsignedStableCandidate) {
    $signTool = Find-SignTool
    foreach ($binary in @(
        (Join-Path $hostPayload "AkuBrowserRuntimeHost.exe"),
        (Join-Path $runtimePayload "AkuSidecar.exe"),
        (Join-Path $runtimePayload "c2patool.exe")
    )) {
        Sign-Binary $binary $signTool
    }
}

if (-not [string]::IsNullOrWhiteSpace($UpdateSigningPrivateKeyPath)) {
    $updateArtifactName = "AkuBrowserRuntime-$($release.version)-windows-x64.zip"
    $updateArtifactPath = Join-Path $OutputRoot $updateArtifactName
    $updateManifestPath = Join-Path $OutputRoot "AkuBrowserRuntimeUpdate.json"
    $unsignedUpdateManifestPath = Join-Path $buildRoot "runtime-update-unsigned.json"
    Reset-Path $updateArtifactPath $OutputRoot
    Reset-Path $updateManifestPath $OutputRoot

    $runtimeUpdateFiles = Get-ChildItem -LiteralPath $runtimePayload -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                path = (Get-RelativePath $runtimePayload $_.FullName).Replace("\", "/")
                size = $_.Length
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
            }
        }
    $runtimeUpdatePayloadManifest = [ordered]@{
        schemaVersion = 1
        product = "AkuBrowser"
        version = $release.version
        architecture = "windows-x64"
        files = @($runtimeUpdateFiles)
    }
    $runtimeUpdatePayloadManifestPath = Join-Path $runtimePayload "payload-manifest.json"
    Write-Utf8NoBom $runtimeUpdatePayloadManifestPath ($runtimeUpdatePayloadManifest | ConvertTo-Json -Depth 8)
    Compress-Archive -Path (Join-Path $runtimePayload "*") -DestinationPath $updateArtifactPath -CompressionLevel Optimal
    Remove-Item -LiteralPath $runtimeUpdatePayloadManifestPath -Force

    $updateArtifactHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $updateArtifactPath).Hash.ToLowerInvariant()
    $unsignedUpdateManifest = [ordered]@{
        schemaVersion = 1
        product = "AkuBrowser"
        channel = "stable"
        version = $release.version
        runtimeRevision = $release.components.akuBridge.runtimeRevision
        bridgeContractVersion = $release.components.akuBridge.contractVersion
        publishedAt = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        artifact = [ordered]@{
            url = "https://github.com/abangkis/AkuBrowser/releases/download/v$($release.version)/$updateArtifactName"
            size = (Get-Item -LiteralPath $updateArtifactPath).Length
            sha256 = $updateArtifactHash
        }
    }
    Write-Utf8NoBom $unsignedUpdateManifestPath ($unsignedUpdateManifest | ConvertTo-Json -Depth 8)
    Push-Location $installerSource
    try {
        $derivedUpdatePublicKey = (& go run .\cmd\sign-update-manifest `
            -manifest $unsignedUpdateManifestPath `
            -private-key $UpdateSigningPrivateKeyPath `
            -output $updateManifestPath | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Runtime update manifest signing failed." }
    }
    finally { Pop-Location }
    Assert-True ($derivedUpdatePublicKey -eq $UpdatePublicKey) "Runtime-update private key does not match the public key pinned into the native host."
}

$payloadFiles = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        [ordered]@{
            path = (Get-RelativePath $payloadRoot $_.FullName).Replace("\", "/")
            size = $_.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        }
    }
$payloadManifest = [ordered]@{
    schemaVersion = 1
    product = "AkuBrowser"
    version = $release.version
    architecture = "windows-x64"
    bridgeIdentityProfile = $BridgeIdentityProfile
    bridgeIdentityDistribution = $selectedBridgeIdentityDistribution
    bridgeIdentityAuthority = "config/bridge-identities.json"
    extensionOrigin = "chrome-extension://$ExtensionId/"
    files = @($payloadFiles)
}
Write-Utf8NoBom (Join-Path $payloadRoot "payload-manifest.json") ($payloadManifest | ConvertTo-Json -Depth 8)

$nsisArguments = @(
    "/V2",
    "/DAPP_VERSION=$($release.version)",
    "/DVERSION_QUAD=$versionQuad",
    "/DPAYLOAD_ROOT=$payloadRoot",
    "/DOUTPUT_FILE=$artifactPath"
)
if ($UnsignedLocalCandidate -or $UnsignedStableCandidate) {
    $nsisArguments += "/DUNSIGNED_BUILD=1"
}
$savedNsisSigningEnvironment = @{
    AKU_NSIS_SIGN_TOOL = $env:AKU_NSIS_SIGN_TOOL
    AKU_NSIS_CERTIFICATE_PATH = $env:AKU_NSIS_CERTIFICATE_PATH
    AKU_NSIS_CERTIFICATE_PASSWORD = $env:AKU_NSIS_CERTIFICATE_PASSWORD
    AKU_NSIS_SIGNING_THUMBPRINT = $env:AKU_NSIS_SIGNING_THUMBPRINT
    AKU_NSIS_TIMESTAMP_URL = $env:AKU_NSIS_TIMESTAMP_URL
}
if (-not $UnsignedLocalCandidate -and -not $UnsignedStableCandidate) {
    $nsisSigningScript = Join-Path $buildRoot "sign-nsis-uninstaller.ps1"
    Write-Utf8NoBom $nsisSigningScript @'
param([Parameter(Mandatory = $true)][string] $Path)
$ErrorActionPreference = "Stop"
$arguments = @(
    "sign",
    "/fd", "SHA256",
    "/tr", $env:AKU_NSIS_TIMESTAMP_URL,
    "/td", "SHA256",
    "/d", "AkuBrowser Runtime",
    "/du", "https://github.com/abangkis/AkuBrowser"
)
if (-not [string]::IsNullOrWhiteSpace($env:AKU_NSIS_CERTIFICATE_PATH)) {
    $arguments += @("/f", $env:AKU_NSIS_CERTIFICATE_PATH)
    if (-not [string]::IsNullOrWhiteSpace($env:AKU_NSIS_CERTIFICATE_PASSWORD)) {
        $arguments += @("/p", $env:AKU_NSIS_CERTIFICATE_PASSWORD)
    }
}
else {
    $arguments += @("/sha1", $env:AKU_NSIS_SIGNING_THUMBPRINT)
}
$arguments += $Path
& $env:AKU_NSIS_SIGN_TOOL @arguments | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $env:AKU_NSIS_SIGN_TOOL verify /pa /all $Path | Out-Host
exit $LASTEXITCODE
'@
    $env:AKU_NSIS_SIGN_TOOL = $signTool
    $env:AKU_NSIS_CERTIFICATE_PATH = $CertificatePath
    $env:AKU_NSIS_CERTIFICATE_PASSWORD = $CertificatePassword
    $env:AKU_NSIS_SIGNING_THUMBPRINT = $SigningThumbprint
    $env:AKU_NSIS_TIMESTAMP_URL = $TimestampUrl
    $nsisArguments += "/DSIGN_UNINSTALLER_SCRIPT=$nsisSigningScript"
}
$nsisArguments += (Join-Path $installerSource "setup.nsi")
try {
    & $nsisCompiler @nsisArguments | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "AkuBrowser Runtime setup wizard build failed."
    }
}
finally {
    foreach ($name in $savedNsisSigningEnvironment.Keys) {
        if ($null -eq $savedNsisSigningEnvironment[$name]) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -Path "Env:$name" -Value $savedNsisSigningEnvironment[$name]
        }
    }
}

if (-not $UnsignedLocalCandidate -and -not $UnsignedStableCandidate) {
    Sign-Binary $artifactPath $signTool
}

$artifactHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash.ToLowerInvariant()
"$artifactHash  $artifactName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII
Reset-Path $buildRoot $OutputRoot

[ordered]@{
    status = "ok"
    version = $release.version
    bridgeIdentityProfile = $BridgeIdentityProfile
    bridgeIdentityDistribution = $selectedBridgeIdentityDistribution
    bridgeIdentityAuthority = "config/bridge-identities.json"
    extensionOrigin = "chrome-extension://$ExtensionId/"
    signed = (-not $UnsignedLocalCandidate -and -not $UnsignedStableCandidate)
    candidate = [bool]($UnsignedLocalCandidate -or $UnsignedStableCandidate)
    releaseChannel = $current.channel
    artifact = $artifactPath
    sha256 = $artifactHash
    bytes = (Get-Item -LiteralPath $artifactPath).Length
    sourceCommits = $sourceCommits
    sourceDirty = @($dirty)
} | ConvertTo-Json -Depth 8
