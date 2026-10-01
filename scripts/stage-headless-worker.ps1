[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $DestinationDirectory,
    [string] $SourceDirectory = "",
    [string] $WorkerLicensePath = "",
    [string] $PinPath = "",
    [string] $ArchivePath = "",
    [string] $CacheRoot = ""
)

$ErrorActionPreference = "Stop"

$browserRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $browserRoot
$sidecarRoot = Join-Path $workspaceRoot "AkuSidecar"
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $sidecarRoot "internal\collection\headless\worker"
}
if ([string]::IsNullOrWhiteSpace($WorkerLicensePath)) {
    $WorkerLicensePath = Join-Path $sidecarRoot "LICENSE"
}
if ([string]::IsNullOrWhiteSpace($PinPath)) {
    $PinPath = Join-Path $browserRoot "release\headless-worker\node.pin.json"
}
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $browserRoot "build\cache\headless-worker"
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-FullPath([string] $Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Assert-ContainedPath([string] $Path, [string[]] $AllowedRoots, [string] $Description) {
    $absolutePath = Get-FullPath $Path
    foreach ($allowedRoot in $AllowedRoots) {
        $absoluteRoot = (Get-FullPath $allowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $prefix = $absoluteRoot + [IO.Path]::DirectorySeparatorChar
        if ($absolutePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $absolutePath
        }
    }
    throw "$Description must be inside an approved project build/artifact directory: $absolutePath"
}

function Assert-NoReparsePoints([string] $Root, [string] $Description) {
    $entries = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)
    foreach ($entry in $entries) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description contains a symbolic link or reparse point: $($entry.FullName)"
        }
    }
}

function Read-NodePin([string] $Path) {
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Node.js release pin was not found: $Path"
    $pin = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Assert-True ([int]$pin.protocol -eq 1) "Node.js release pin protocol must be 1."
    Assert-True ([string]$pin.platform -eq "win-x64") "Node.js release pin must select Windows x64."
    Assert-True ([string]$pin.nodeVersion -match '^\d+\.\d+\.\d+$') "Node.js release pin version is invalid."
    Assert-True ([string]$pin.license -eq "MIT") "Node.js release pin must identify the upstream MIT license."
    Assert-True ([string]$pin.licenseFile -eq "LICENSE") "Node.js release pin must preserve the upstream LICENSE file."
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$pin.licenseSourceUrl)) "Node.js release pin must record the upstream license source."
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$pin.licenseNotice)) "Node.js release pin must describe the bundled third-party notices."
    Assert-True ([string]$pin.distributionSha256 -match '^[0-9a-fA-F]{64}$') "Node.js release pin distributionSha256 must be a SHA-256 digest."
    $archiveName = "node-v$($pin.nodeVersion)-win-x64.zip"
    $expectedUrl = "https://nodejs.org/dist/v$($pin.nodeVersion)/$archiveName"
    Assert-True ([string]$pin.officialDistributionUrl -ceq $expectedUrl) "Node.js release pin URL is not the exact official Windows x64 archive URL."
    $expectedChecksumUrl = "https://nodejs.org/dist/v$($pin.nodeVersion)/SHASUMS256.txt"
    Assert-True ([string]$pin.officialChecksumUrl -ceq $expectedChecksumUrl) "Node.js release pin checksum URL is not the official checksum list URL."
    return $pin
}

$browserBuildRoot = Join-Path $browserRoot "build"
$browserArtifactRoot = Join-Path $browserRoot "artifacts"
$sidecarBuildRoot = Join-Path $sidecarRoot "build"
$DestinationDirectory = Assert-ContainedPath $DestinationDirectory @($browserBuildRoot, $browserArtifactRoot, $sidecarBuildRoot) "Staging destination"
$SourceDirectory = Get-FullPath $SourceDirectory
$WorkerLicensePath = Get-FullPath $WorkerLicensePath
$PinPath = Get-FullPath $PinPath
$CacheRoot = Assert-ContainedPath $CacheRoot @($browserBuildRoot, $sidecarBuildRoot) "Node.js cache"
Assert-True (Test-Path -LiteralPath $SourceDirectory -PathType Container) "Headless worker source directory was not found: $SourceDirectory"
Assert-True (Test-Path -LiteralPath $WorkerLicensePath -PathType Leaf) "AkuSidecar source license was not found: $WorkerLicensePath"
$pin = Read-NodePin $PinPath
$archiveName = "node-v$($pin.nodeVersion)-win-x64.zip"
$expectedArchiveHash = ([string]$pin.distributionSha256).ToLowerInvariant()

New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $versionCache = Join-Path $CacheRoot ([string]$pin.nodeVersion)
    New-Item -ItemType Directory -Force -Path $versionCache | Out-Null
    $ArchivePath = Join-Path $versionCache $archiveName
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        Write-Verbose "Downloading the pinned official Node.js archive to $ArchivePath"
        $partialArchivePath = Join-Path $versionCache ("." + $archiveName + ".download-" + [Guid]::NewGuid().ToString("n"))
        $downloadScript = @'
const fs = require('node:fs');
const https = require('node:https');
const { pipeline } = require('node:stream/promises');
const url = process.argv[1];
const output = process.argv[2];
function download(target, redirects = 0) {
  const parsed = new URL(target);
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'nodejs.org') throw new Error('Refusing non-official or non-HTTPS Node.js download URL');
  if (redirects > 5) throw new Error('Too many redirects while downloading Node.js');
  return new Promise((resolve, reject) => {
    const request = https.get(parsed, (response) => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        const next = new URL(response.headers.location || '', parsed);
        response.resume();
        download(next.href, redirects + 1).then(resolve, reject);
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Node.js download returned HTTP ${response.statusCode}`));
        return;
      }
      pipeline(response, fs.createWriteStream(output, { flags: 'wx' })).then(resolve, reject);
    });
    request.setTimeout(180000, () => request.destroy(new Error('Node.js download timed out')));
    request.on('error', reject);
  });
}
download(url).catch((error) => { console.error(error.message); process.exitCode = 1; });
'@
        try {
            & node --use-system-ca -e $downloadScript ([string]$pin.officialDistributionUrl) $partialArchivePath
            if ($LASTEXITCODE -ne 0) { throw "Official Node.js archive download failed." }
            Move-Item -LiteralPath $partialArchivePath -Destination $ArchivePath
        }
        finally {
            if (Test-Path -LiteralPath $partialArchivePath) {
                Remove-Item -LiteralPath $partialArchivePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
$ArchivePath = Get-FullPath $ArchivePath
Assert-True (Test-Path -LiteralPath $ArchivePath -PathType Leaf) "Node.js archive was not found: $ArchivePath"
$actualArchiveHash = Get-Sha256 $ArchivePath
Assert-True ($actualArchiveHash -eq $expectedArchiveHash) "Node.js official distribution SHA-256 differs from release/headless-worker/node.pin.json. Expected $expectedArchiveHash, got $actualArchiveHash."

$sourceFiles = @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File -Force | Where-Object {
    $relativePath = [Uri]::UnescapeDataString(([Uri]((Get-FullPath $SourceDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar)).MakeRelativeUri([Uri]$_.FullName).ToString())
    $relativePath -notmatch '(^|/)(test|node_modules|\.git)/'
})
Assert-True ($sourceFiles.Count -gt 0) "No headless worker runtime sources were found in $SourceDirectory"
Assert-NoReparsePoints $SourceDirectory "Headless worker source"
$workerLicenseItem = Get-Item -LiteralPath $WorkerLicensePath -Force
Assert-True (($workerLicenseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "AkuSidecar source license is a reparse point: $WorkerLicensePath"

$stageParent = Split-Path -Parent $DestinationDirectory
New-Item -ItemType Directory -Force -Path $stageParent | Out-Null
$stageDirectory = Join-Path $stageParent (".headless-worker-stage-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $stageDirectory | Out-Null
$expandedArchive = Join-Path $CacheRoot (".expanded-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $expandedArchive | Out-Null

try {
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $expandedArchive -Force
    $expectedArchiveRoot = "node-v$($pin.nodeVersion)-win-x64"
    $nodeSource = Join-Path $expandedArchive (Join-Path $expectedArchiveRoot "node.exe")
    $licenseSource = Join-Path $expandedArchive (Join-Path $expectedArchiveRoot ([string]$pin.licenseFile))
    Assert-True (Test-Path -LiteralPath $nodeSource -PathType Leaf) "Official Node.js archive is missing $expectedArchiveRoot/node.exe."
    Assert-True (Test-Path -LiteralPath $licenseSource -PathType Leaf) "Official Node.js archive is missing $expectedArchiveRoot/$($pin.licenseFile)."

    Copy-Item -LiteralPath $nodeSource -Destination (Join-Path $stageDirectory "node.exe")
    Copy-Item -LiteralPath $licenseSource -Destination (Join-Path $stageDirectory ([string]$pin.licenseFile))
    Copy-Item -LiteralPath $WorkerLicensePath -Destination (Join-Path $stageDirectory "LICENSE-AkuSidecar")
    foreach ($sourceFile in $sourceFiles) {
        $relativePath = [Uri]::UnescapeDataString(([Uri]((Get-FullPath $SourceDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar)).MakeRelativeUri([Uri]$sourceFile.FullName).ToString())
        $destinationPath = Join-Path $stageDirectory ($relativePath.Replace("/", [IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath
    }

    $nodeExecutableHash = Get-Sha256 (Join-Path $stageDirectory "node.exe")
    $licenseHash = Get-Sha256 (Join-Path $stageDirectory ([string]$pin.licenseFile))
    $workerLicenseHash = Get-Sha256 (Join-Path $stageDirectory "LICENSE-AkuSidecar")
    $packagedPin = [ordered]@{
        protocol = 1
        nodeVersion = [string]$pin.nodeVersion
        nodeSha256 = $nodeExecutableHash
        distributionSha256 = $actualArchiveHash
        officialDistributionUrl = [string]$pin.officialDistributionUrl
        officialChecksumUrl = [string]$pin.officialChecksumUrl
        license = [string]$pin.license
        licenseFile = [string]$pin.licenseFile
        licenseSha256 = $licenseHash
        licenseSourceUrl = [string]$pin.licenseSourceUrl
        licenseNotice = [string]$pin.licenseNotice
        source = "Node.js official Windows x64 binary archive"
    }
    [IO.File]::WriteAllText((Join-Path $stageDirectory "node.pin.json"), ($packagedPin | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $DestinationDirectory) {
        $destinationItem = Get-Item -LiteralPath $DestinationDirectory -Force
        Assert-True (($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Staging destination is a reparse point: $DestinationDirectory"
        Remove-Item -LiteralPath $DestinationDirectory -Recurse -Force
    }
    Move-Item -LiteralPath $stageDirectory -Destination $DestinationDirectory

    [ordered]@{
        status = "ok"
        destinationDirectory = $DestinationDirectory
        nodeVersion = [string]$pin.nodeVersion
        nodeSha256 = $nodeExecutableHash
        distributionSha256 = $actualArchiveHash
        officialDistributionUrl = [string]$pin.officialDistributionUrl
        licenseSha256 = $licenseHash
        workerLicenseSha256 = $workerLicenseHash
        workerSourceFiles = $sourceFiles.Count
    } | ConvertTo-Json -Depth 6
}
finally {
    if (Test-Path -LiteralPath $stageDirectory) {
        Remove-Item -LiteralPath $stageDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $expandedArchive) {
        Remove-Item -LiteralPath $expandedArchive -Recurse -Force -ErrorAction SilentlyContinue
    }
}
