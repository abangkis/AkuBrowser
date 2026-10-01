[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $browserRoot ("build\headless-worker-packaging-tests\" + [Guid]::NewGuid().ToString("n"))
$sourceRoot = Join-Path $testRoot "source"
$archiveRoot = Join-Path $testRoot "archive"
$archivePath = Join-Path $testRoot "fixture-node.zip"
$pinPath = Join-Path $testRoot "node.pin.json"
$workerLicensePath = Join-Path $testRoot "AkuSidecar-LICENSE"
$destination = Join-Path $testRoot "output\headless-worker"
$helperPath = Join-Path $PSScriptRoot "stage-headless-worker.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force -Path $sourceRoot, $archiveRoot | Out-Null
$nodeVersion = "24.16.0"
$fixtureDistribution = Join-Path $archiveRoot "node-v$nodeVersion-win-x64"
$fixtureVendor = Join-Path $sourceRoot "vendor"
$fixtureTest = Join-Path $sourceRoot "test"
$fixtureNodeModules = Join-Path $sourceRoot "node_modules"
New-Item -ItemType Directory -Force -Path $fixtureDistribution, $fixtureVendor, $fixtureTest, $fixtureNodeModules | Out-Null
[IO.File]::WriteAllText((Join-Path $fixtureDistribution "node.exe"), "fixture-node-executable", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureDistribution "LICENSE"), "Fixture Node license and third-party notices.", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $sourceRoot "worker.mjs"), "export const fixtureWorker = true;`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $sourceRoot "worker-helper.mjs"), "export const helper = true;`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $sourceRoot "package.json"), '{"type":"module"}', [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($workerLicensePath, "Fixture AkuSidecar Apache-2.0 license.", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureVendor "source.js"), "export const vendor = true;`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureTest "worker.test.mjs"), "throw new Error('test files must not ship');`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureNodeModules "package.js"), "throw new Error('node_modules must not ship');`n", [Text.UTF8Encoding]::new($false))
[IO.Compression.ZipFile]::CreateFromDirectory($archiveRoot, $archivePath)
$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
$pin = [ordered]@{
    protocol = 1
    nodeVersion = $nodeVersion
    platform = "win-x64"
    officialDistributionUrl = "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-win-x64.zip"
    distributionSha256 = $archiveHash
    officialChecksumUrl = "https://nodejs.org/dist/v$nodeVersion/SHASUMS256.txt"
    license = "MIT"
    licenseFile = "LICENSE"
    licenseSourceUrl = "https://github.com/nodejs/node/blob/v$nodeVersion/LICENSE"
    licenseNotice = "Fixture license text stands in for the full upstream Node.js LICENSE."
}
[IO.File]::WriteAllText($pinPath, ($pin | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

try {
    $stageText = & $helperPath `
        -DestinationDirectory $destination `
        -SourceDirectory $sourceRoot `
        -WorkerLicensePath $workerLicensePath `
        -PinPath $pinPath `
        -ArchivePath $archivePath `
        -CacheRoot (Join-Path $browserRoot ("build\headless-worker-packaging-tests\cache\" + [Guid]::NewGuid().ToString("n")))
    $result = ($stageText | Out-String) | ConvertFrom-Json
    $manifestPath = Join-Path $destination "node.pin.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-True ($result.status -eq "ok") "Headless worker fixture staging did not report success."
    Assert-True ($manifest.protocol -eq 1 -and $manifest.nodeVersion -eq $nodeVersion) "Packaged Node.js pin protocol or version is incorrect."
    Assert-True ($manifest.distributionSha256 -eq $archiveHash) "Packaged Node.js pin does not retain the verified archive digest."
    Assert-True ($manifest.officialDistributionUrl -eq $pin.officialDistributionUrl -and $manifest.officialChecksumUrl -eq $pin.officialChecksumUrl) "Packaged Node.js pin does not retain official distribution provenance."
    Assert-True ($manifest.license -eq "MIT" -and $manifest.licenseFile -eq "LICENSE" -and -not [string]::IsNullOrWhiteSpace([string]$manifest.licenseNotice)) "Packaged Node.js license provenance is incomplete."
    Assert-True ($manifest.nodeSha256 -eq ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $destination "node.exe")).Hash.ToLowerInvariant())) "Packaged nodeSha256 does not match node.exe."
    Assert-True (Test-Path -LiteralPath (Join-Path $destination "LICENSE") -PathType Leaf) "The Node.js license was not staged."
    Assert-True (Test-Path -LiteralPath (Join-Path $destination "LICENSE-AkuSidecar") -PathType Leaf) "The AkuSidecar worker license was not staged."
    Assert-True ($manifest.licenseSha256 -eq ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $destination "LICENSE")).Hash.ToLowerInvariant())) "Packaged license digest does not match the staged upstream license file."
    Assert-True ($result.workerLicenseSha256 -eq ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $destination "LICENSE-AkuSidecar")).Hash.ToLowerInvariant())) "Staging result does not report the copied AkuSidecar worker license hash."
    Assert-True (Test-Path -LiteralPath (Join-Path $destination "worker.mjs") -PathType Leaf) "worker.mjs was not staged."
    Assert-True (Test-Path -LiteralPath (Join-Path $destination "worker-helper.mjs") -PathType Leaf) "Sibling worker module was not staged."
    Assert-True (Test-Path -LiteralPath (Join-Path $destination "vendor\source.js") -PathType Leaf) "Vendored worker dependency was not staged."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination "test") -PathType Container)) "Worker test files leaked into the runtime package."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination "node_modules") -PathType Container)) "Worker node_modules leaked into the runtime package."

    $badPinPath = Join-Path $testRoot "bad-node.pin.json"
    $pin.distributionSha256 = "0" * 64
    $badPin = $pin
    [IO.File]::WriteAllText($badPinPath, ($badPin | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $badDestination = Join-Path $testRoot "bad-output\headless-worker"
    $rejected = $false
    try {
        & $helperPath `
            -DestinationDirectory $badDestination `
            -SourceDirectory $sourceRoot `
            -WorkerLicensePath $workerLicensePath `
            -PinPath $badPinPath `
            -ArchivePath $archivePath `
            -CacheRoot (Join-Path $browserRoot ("build\headless-worker-packaging-tests\cache\" + [Guid]::NewGuid().ToString("n"))) | Out-Null
    }
    catch { $rejected = $true }
    Assert-True $rejected "A mismatched official distribution digest was not rejected."
    Assert-True (-not (Test-Path -LiteralPath $badDestination)) "A mismatched Node.js archive created a staged runtime directory."

    [ordered]@{
        status = "ok"
        nodeVersion = $manifest.nodeVersion
        nodeSha256 = $manifest.nodeSha256
        distributionSha256 = $manifest.distributionSha256
        stagedSourceFiles = [int]$result.workerSourceFiles
        rejectedBadArchiveHash = $rejected
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $fullTestRoot = [IO.Path]::GetFullPath($testRoot)
        $buildRoot = [IO.Path]::GetFullPath((Join-Path $browserRoot "build")).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $fullTestRoot.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove the headless worker test fixture outside Browser/build: $fullTestRoot"
        }
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
