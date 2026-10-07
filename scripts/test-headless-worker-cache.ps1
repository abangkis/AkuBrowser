param([string] $ArchivePath = '')
$ErrorActionPreference = 'Stop'
$browserRoot = Split-Path -Parent $PSScriptRoot
$sidecarRoot = Join-Path (Split-Path -Parent $browserRoot) 'AkuSidecar'
$pin = Get-Content -LiteralPath (Join-Path $browserRoot 'release/headless-worker/node.pin.json') -Raw | ConvertFrom-Json
if (-not $ArchivePath) {
    $ArchivePath = Join-Path $browserRoot "build/cache/headless-worker/$($pin.nodeVersion)/node-v$($pin.nodeVersion)-win-x64.zip"
}
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw 'An existing pinned archive is required; this test never downloads Node.js.'
}
$root = Join-Path $browserRoot ('build/node-cache-tests/' + [Guid]::NewGuid().ToString('n'))
$cache = Join-Path $root 'cache'
$source = Join-Path $root 'worker'
. (Join-Path $PSScriptRoot 'output-lifecycle.ps1')
$outputOwner = Start-AkuOutput -Family 'node-cache-test' -Paths @($root) -ReserveBytes 402653184
try {
New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sidecarRoot 'internal/collection/headless/worker') -Destination $source -Recurse
function Invoke-Stage([string] $Name) {
    $text = & (Join-Path $PSScriptRoot 'stage-headless-worker.ps1') -DestinationDirectory (Join-Path $root $Name) -CacheRoot $cache -ArchivePath $ArchivePath -SourceDirectory $source
    $result = ($text | Out-String) | ConvertFrom-Json
    if ($result.status -ne 'ok') { throw 'Staging failed.' }
    return $result
}
$first = Invoke-Stage 'first'
if ($first.nodeFilesCacheReused) { throw 'First staging incorrectly reused a nonexistent cache.' }
[IO.File]::WriteAllText((Join-Path $source 'cache-test-fresh.mjs'), 'export const fresh = true;')
$second = Invoke-Stage 'second'
if (-not $second.nodeFilesCacheReused -or $second.nodeSha256 -ne $first.nodeSha256) { throw 'Verified cache was not reused.' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'second/cache-test-fresh.mjs'))) { throw 'Cache reuse froze worker sources.' }
$entries = @(Get-ChildItem -LiteralPath $cache -Directory | Where-Object { $_.Name -like 'files-*' })
if ($entries.Count -ne 1) { throw 'Extracted cache identity is ambiguous.' }
[IO.File]::WriteAllText((Join-Path $entries[0].FullName 'LICENSE'), 'deliberately corrupt fixture cache')
$third = Invoke-Stage 'recovered'
if ($third.nodeFilesCacheReused -or $third.licenseSha256 -ne $first.licenseSha256) { throw 'Corrupt cache was not rebuilt from the verified archive.' }
$badArchive = Join-Path $root 'untrusted.zip'
[IO.File]::WriteAllText($badArchive, 'not the official pinned archive')
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'stage-headless-worker.ps1') -DestinationDirectory (Join-Path $root 'rejected') -CacheRoot $cache -ArchivePath $badArchive -SourceDirectory $source | Out-Null
} catch {
    if ($_.Exception.Message -notlike '*official distribution SHA-256 differs*') { throw }
    $rejected = $true
}
if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $root 'rejected'))) { throw 'An untrusted archive was accepted or promoted.' }
[ordered]@{ status = 'ok'; cold = $true; warm = $true; freshWorkerSources = $true; corruptCacheRecovered = $true; untrustedArchiveRejected = $true; evidenceRoot = $root } | ConvertTo-Json
Complete-AkuOutput -Id $outputOwner
} catch {
    Complete-AkuOutput -Id $outputOwner -Failed
    throw
}
