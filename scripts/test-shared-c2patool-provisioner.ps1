$ErrorActionPreference = 'Stop'
$browserRoot = Split-Path -Parent $PSScriptRoot
$provisionerSource = Join-Path $PSScriptRoot 'provision-shared-c2patool.ps1'
$fixtureRoot = Join-Path $browserRoot ('.test-fixtures\c2patool-resolver-' + [Guid]::NewGuid().ToString('N'))
$fixtureJunctions = @()

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function New-TestJunction([string] $Path, [string] $Target) {
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    $script:fixtureJunctions += $Path
}

function New-ProvisionerFixture([string] $Name, [string] $ExpectedHash) {
    $root = Join-Path $fixtureRoot $Name
    $workspaceRoot = Join-Path $root 'workspace'
    $fixtureBrowserRoot = Join-Path $workspaceRoot 'AkuBrowser'
    $scriptRoot = Join-Path $fixtureBrowserRoot 'scripts'
    $sidecarSource = Join-Path $workspaceRoot 'AkuSidecar\runtime\dev\c2patool.exe'
    $innerSharedRoot = Join-Path $workspaceRoot 'SharedTemp'
    $outerSharedRoot = Join-Path $root 'SharedTemp'
    New-Item -ItemType Directory -Force -Path $scriptRoot, (Split-Path -Parent $sidecarSource), $innerSharedRoot, $outerSharedRoot | Out-Null
    Copy-Item -LiteralPath $provisionerSource -Destination (Join-Path $scriptRoot 'provision-shared-c2patool.ps1')
    [IO.File]::WriteAllBytes($sidecarSource, [Text.Encoding]::UTF8.GetBytes('synthetic resolver fixture; not a c2patool binary'))
    $manifest = [ordered]@{
        components = [ordered]@{
            c2paTool = [ordered]@{
                workspaceSource = '../SharedTemp/AkuBrowser/shared-tools/c2patool/0.26.60/windows-x64/c2patool.exe'
                sha256 = $ExpectedHash
                version = '0.26.60'
            }
        }
    }
    $manifestPath = Join-Path $fixtureBrowserRoot 'release\release-manifest.json'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath) | Out-Null
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        root = $root
        provisioner = Join-Path $scriptRoot 'provision-shared-c2patool.ps1'
        source = $sidecarSource
        innerSharedRoot = $innerSharedRoot
        outerSharedRoot = $outerSharedRoot
        target = Join-Path $innerSharedRoot 'AkuBrowser\shared-tools\c2patool\0.26.60\windows-x64\c2patool.exe'
        outerTarget = Join-Path $outerSharedRoot 'AkuBrowser\shared-tools\c2patool\0.26.60\windows-x64\c2patool.exe'
    }
}

try {
    Assert-True (-not (Test-Path -LiteralPath $fixtureRoot)) "Resolver fixture path already exists: $fixtureRoot"
    New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

    $validSourceBytes = [Text.Encoding]::UTF8.GetBytes('synthetic resolver fixture; not a c2patool binary')
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $validHash = [BitConverter]::ToString($sha256.ComputeHash($validSourceBytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
    $validFixture = New-ProvisionerFixture 'valid' $validHash
    $resolvedPath = (& $validFixture.provisioner | Out-String).Trim()
    Assert-True ($resolvedPath -eq [IO.Path]::GetFullPath($validFixture.target)) "Provisioner did not select the nearest SharedTemp: $resolvedPath"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $validFixture.target).Hash.ToLowerInvariant() -eq $validHash) 'Provisioned fixture hash differs from its pin.'
    Assert-True (-not (Test-Path -LiteralPath $validFixture.outerTarget)) 'Provisioner wrote the fixture under the outer SharedTemp.'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $validFixture.target) -Filter 'c2patool.exe.*.tmp' -Force).Count -eq 0) 'Provisioner left a staging file after promotion.'

    $mismatchFixture = New-ProvisionerFixture 'mismatch' ('0' * 64)
    $rejectedMismatch = $false
    try {
        $null = & $mismatchFixture.provisioner
    } catch {
        $rejectedMismatch = $true
    }
    Assert-True $rejectedMismatch 'Provisioner accepted a source whose hash differs from the manifest pin.'
    Assert-True (-not (Test-Path -LiteralPath $mismatchFixture.target)) 'A mismatched c2patool source was promoted.'
    Assert-True (-not (Test-Path -LiteralPath (Split-Path -Parent $mismatchFixture.target))) 'Provisioner created the target directory before rejecting a mismatched source.'
    Assert-True (@(Get-ChildItem -LiteralPath $mismatchFixture.innerSharedRoot -Recurse -Filter 'c2patool.exe.*.tmp' -Force).Count -eq 0) 'Provisioner left a staging file after rejecting a mismatched source.'

    $destinationFixture = New-ProvisionerFixture 'destination-junction' $validHash
    $destinationRedirectRoot = Join-Path $destinationFixture.root 'destination-redirect'
    New-Item -ItemType Directory -Force -Path $destinationRedirectRoot | Out-Null
    New-TestJunction (Join-Path $destinationFixture.innerSharedRoot 'AkuBrowser') $destinationRedirectRoot
    $rejectedDestinationJunction = $false
    try {
        $null = & $destinationFixture.provisioner
    } catch {
        $rejectedDestinationJunction = $_.Exception.Message -match 'reparse point'
    }
    Assert-True $rejectedDestinationJunction 'Provisioner did not reject a junction in the SharedTemp target ancestry.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destinationRedirectRoot 'shared-tools'))) 'Provisioner wrote through a junction in the target ancestry.'

    $sourceFixture = New-ProvisionerFixture 'source-junction' $validHash
    $sourceDevRoot = Split-Path -Parent $sourceFixture.source
    $sourceRuntimeRoot = Split-Path -Parent $sourceDevRoot
    Remove-Item -LiteralPath $sourceFixture.source -Force
    Remove-Item -LiteralPath $sourceDevRoot -Recurse -Force
    Remove-Item -LiteralPath $sourceRuntimeRoot -Force
    $sourceRedirectRoot = Join-Path $sourceFixture.root 'source-redirect'
    $redirectedSource = Join-Path $sourceRedirectRoot 'dev\c2patool.exe'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $redirectedSource) | Out-Null
    [IO.File]::WriteAllBytes($redirectedSource, $validSourceBytes)
    New-TestJunction $sourceRuntimeRoot $sourceRedirectRoot
    $rejectedSourceJunction = $false
    try {
        $null = & $sourceFixture.provisioner
    } catch {
        $rejectedSourceJunction = $_.Exception.Message -match 'reparse point'
    }
    Assert-True $rejectedSourceJunction 'Provisioner did not reject a junction in the workspace source ancestry.'
    Assert-True (-not (Test-Path -LiteralPath $sourceFixture.target)) 'Provisioner promoted a source reached through a workspace junction.'
    Assert-True (-not (Test-Path -LiteralPath (Split-Path -Parent $sourceFixture.target))) 'Provisioner created the target directory before rejecting a source ancestry junction.'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $redirectedSource).Hash.ToLowerInvariant() -eq $validHash) 'Provisioner changed the redirected source fixture.'

    Write-Output 'Shared c2patool provisioner resolver tests passed.'
} finally {
    foreach ($junctionPath in $fixtureJunctions) {
        if (Test-Path -LiteralPath $junctionPath) {
            Remove-Item -LiteralPath $junctionPath -Force
        }
    }
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
