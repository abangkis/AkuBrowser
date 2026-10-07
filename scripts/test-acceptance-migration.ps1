#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$browserRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar)
$artifactsRoot = Join-Path $browserRoot "artifacts"
$sandboxRoot = Join-Path $artifactsRoot (".acceptance-migration-test-" + [Guid]::NewGuid().ToString("N"))
$migrationScript = Join-Path $PSScriptRoot "migrate-build-state.ps1"
$acceptanceScript = Join-Path $PSScriptRoot "start-installed-app-acceptance.ps1"
$previousCimFunction = Get-Command Get-CimInstance -CommandType Function -ErrorAction SilentlyContinue
$previousCimBody = if ($null -ne $previousCimFunction) { $previousCimFunction.ScriptBlock } else { $null }
$global:AcceptanceMigrationTestProcesses = @()
function global:Get-CimInstance {
    [CmdletBinding()]
    param(
        [string] $ClassName,
        [string[]] $Property
    )
    if ($ClassName -ne "Win32_Process") { throw "Unexpected process inventory class in focused test." }
    return @($global:AcceptanceMigrationTestProcesses)
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Namespace([string] $Path) {
    $digest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))
    return "AkuBrowserTest-" + [Convert]::ToHexString($digest).Substring(0, 16).ToLowerInvariant()
}

function Invoke-Migration(
    [ValidateSet("build", "artifacts")]
    [string] $OutputClass = "build",
    [switch] $Apply
) {
    $arguments = @{ BrowserRoot = $sandboxRoot; OutputClass = $OutputClass }
    if ($Apply) { $arguments.Apply = $true }
    $raw = & $migrationScript @arguments | Out-String
    return $raw | ConvertFrom-Json
}

function Invoke-AcceptancePlan([string] $AcceptanceRoot) {
    $raw = & $acceptanceScript `
        -BrowserRoot $sandboxRoot `
        -TupleDirectory $tupleRoot `
        -AcceptanceRoot $AcceptanceRoot `
        -PlanOnly | Out-String
    return $raw | ConvertFrom-Json
}

try {
    [void][IO.Directory]::CreateDirectory($sandboxRoot)
    $buildRoot = Join-Path $sandboxRoot "build"
    $legacyRoot = Join-Path $sandboxRoot "acceptance-state\legacy-build"
    $tupleRoot = Join-Path $sandboxRoot "artifacts\tuple"
    $releaseRoot = Join-Path $sandboxRoot "artifacts\old-release-output"
    $releasePayload = Join-Path $releaseRoot "package\runtime.bin"
    $acceptanceItem = Join-Path $buildRoot "qa-acceptance"
    $originalProfileFile = Join-Path $acceptanceItem "LocalAppData\AkuBrowser\data\profile.bin"
    $gitAsset = Join-Path $acceptanceItem ".git\ignored-assets\cache.dat"
    $emptyDirectory = Join-Path $acceptanceItem "empty-directory"

    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $originalProfileFile))
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $gitAsset))
    [void][IO.Directory]::CreateDirectory($emptyDirectory)
    [void][IO.Directory]::CreateDirectory($tupleRoot)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $releasePayload))
    [IO.File]::WriteAllBytes($originalProfileFile, [byte[]](0, 1, 2, 3, 10, 255))
    [IO.File]::WriteAllText($gitAsset, "preserved ignored git asset", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $tupleRoot "AkuBrowserLauncher.exe"), "fixture launcher", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($releasePayload, "legacy release payload", [Text.UTF8Encoding]::new($false))
    $releasePayloadHash = (Get-FileHash -LiteralPath $releasePayload -Algorithm SHA256).Hash.ToLowerInvariant()
    $originalProfileHash = (Get-FileHash -LiteralPath $originalProfileFile -Algorithm SHA256).Hash.ToLowerInvariant()

    [void][IO.Directory]::CreateDirectory($buildRoot)

    $dryRun = Invoke-Migration
    Assert-True ($dryRun.mode -eq "dry-run") "Default migration mode must be dry-run."
    Assert-True ((Test-Path -LiteralPath (Join-Path $sandboxRoot "acceptance-state")) -eq $false) "Dry-run created acceptance-state."
    Assert-True (Test-Path -LiteralPath $acceptanceItem -PathType Container) "Dry-run moved the acceptance fixture."
    Assert-True (@($dryRun.results | Where-Object { $_.name -eq "qa-acceptance" -and $_.status -eq "planned" }).Count -eq 1) "Dry-run did not report the acceptance fixture as planned."

    $global:AcceptanceMigrationTestProcesses = @([pscustomobject]@{
        ProcessId = 424242
        ExecutablePath = $originalProfileFile
        CommandLine = $null
    })
    $activeRun = Invoke-Migration
    Assert-True (@($activeRun.results | Where-Object { $_.name -eq "qa-acceptance" -and $_.reason -eq "active-process-reference" }).Count -eq 1) "Migration did not skip a process-referenced root."
    $global:AcceptanceMigrationTestProcesses = @()

    $applyResult = Invoke-Migration -Apply
    $movedResult = @($applyResult.results | Where-Object { $_.name -eq "qa-acceptance" -and $_.status -eq "moved" })
    Assert-True ($movedResult.Count -eq 1) "Apply did not move the acceptance fixture successfully."
    Assert-True (-not (Test-Path -LiteralPath $acceptanceItem)) "Migration left the original direct child in build."
    $movedRoot = Join-Path $legacyRoot "qa-acceptance"
    Assert-True (Test-Path -LiteralPath (Join-Path $movedRoot ".git\ignored-assets\cache.dat") -PathType Leaf) "Migration did not preserve the nested .git asset."
    Assert-True (Test-Path -LiteralPath (Join-Path $movedRoot "empty-directory") -PathType Container) "Migration did not preserve the empty directory."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $movedRoot "LocalAppData\AkuBrowser\data\profile.bin") -Algorithm SHA256).Hash.ToLowerInvariant() -eq $originalProfileHash) "The moved profile file did not retain its original SHA."

    $receiptFiles = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRoot "acceptance-state\migration-receipts") -Filter "*.json" -File)
    $receipt = $null
    $acceptanceReceiptPath = $null
    foreach ($receiptFile in $receiptFiles) {
        $candidateReceipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json
        if ($candidateReceipt.destinationPath -eq $movedRoot) { $receipt = $candidateReceipt; $acceptanceReceiptPath = $receiptFile.FullName; break }
    }
    Assert-True ($null -ne $receipt -and $receipt.status -eq "moved") "Migration did not write a completed receipt outside build."
    Assert-True ($receipt.byteCount -gt 0 -and $receipt.fileCount -eq 2) "Receipt byte/file counts do not match the fixture."
    Assert-True ($receipt.manifest.Count -ge 5) "Receipt SHA manifest is incomplete."
    foreach ($entry in @($receipt.manifest | Where-Object { $_.type -eq "file" })) {
        $relative = ([string]$entry.path).Replace("/", [IO.Path]::DirectorySeparatorChar)
        $filePath = if ($relative -eq ".") { $movedRoot } else { Join-Path $movedRoot $relative }
        $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($actualHash -eq [string]$entry.sha256) "Receipt SHA does not match moved content: $relative"
    }
    $expectedNamespace = Get-Namespace $acceptanceItem
    Assert-True ([string]$receipt.originalCredentialNamespace -eq $expectedNamespace) "Receipt did not preserve the original credential namespace."

    $acceptancePlan = Invoke-AcceptancePlan $movedRoot
    Assert-True ([string]$acceptancePlan.credentialNamespace -eq $expectedNamespace) "Acceptance runner did not restore the original credential namespace."
    [void][IO.Directory]::CreateDirectory((Join-Path $legacyRoot "unreceipted-acceptance"))
    $missingReceiptRejected = $false
    try { [void](Invoke-AcceptancePlan (Join-Path $legacyRoot "unreceipted-acceptance")) } catch { $missingReceiptRejected = $true }
    Assert-True $missingReceiptRejected "Acceptance runner accepted a legacy root without its namespace receipt."
    $outsideAcceptance = Join-Path $sandboxRoot "outside-acceptance"
    $containmentRejected = $false
    try { [void](Invoke-AcceptancePlan $outsideAcceptance) } catch { $containmentRejected = $true }
    Assert-True $containmentRejected "Acceptance runner accepted a root outside acceptance-state."

    $reparseRejected = [Collections.Generic.List[string]]::new()
    foreach ($scriptPath in @($migrationScript, $acceptanceScript)) {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        Assert-True ($parseErrors.Count -eq 0) "A script has parse errors while checking its reparse guard."
        $helper = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Assert-NoReparseAttributes" }, $true) | Select-Object -First 1
        Assert-True ($null -ne $helper) "A script is missing its reparse attribute guard."
        Invoke-Expression $helper.Extent.Text
        try {
            Assert-NoReparseAttributes ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint) "Synthetic fixture"
        } catch {
            $reparseRejected.Add($scriptPath)
        }
    }
    Assert-True ($reparseRejected.Count -eq 2) "The migration and acceptance path guards must reject reparse attributes."

    $migrationTokens = $null
    $migrationErrors = $null
    $migrationAst = [Management.Automation.Language.Parser]::ParseFile($migrationScript, [ref]$migrationTokens, [ref]$migrationErrors)
    foreach ($helperName in @("Get-FullPath", "Test-ProcessReferencesPath")) {
        $helper = $migrationAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $helperName }, $true) | Select-Object -First 1
        Assert-True ($null -ne $helper) "Migration is missing helper $helperName."
        Invoke-Expression $helper.Extent.Text
    }
    $activeSnapshot = [pscustomobject]@{ available = $true; rows = @([pscustomobject]@{ ExecutablePath = $originalProfileFile; CommandLine = $null }) }
    Assert-True (Test-ProcessReferencesPath $activeSnapshot $acceptanceItem $true) "Executable-path matching did not protect a referenced root."
    $commandLineSnapshot = [pscustomobject]@{ available = $true; rows = @([pscustomobject]@{ ExecutablePath = $null; CommandLine = "fixture --profile `"$acceptanceItem\LocalAppData`"" }) }
    Assert-True (Test-ProcessReferencesPath $commandLineSnapshot $acceptanceItem $true) "Command-line matching did not protect a referenced root."
    Assert-True (-not (Test-ProcessReferencesPath ([pscustomobject]@{ available = $true; rows = @() }) $acceptanceItem $true)) "An unreferenced root was treated as active."

    $receiptBeforeRepeat = Get-Content -LiteralPath $acceptanceReceiptPath -Raw
    $repeat = Invoke-Migration -Apply
    Assert-True (-not (Test-Path -LiteralPath $acceptanceItem)) "Repeated migration changed the original build state."
    Assert-True ((Get-Content -LiteralPath $acceptanceReceiptPath -Raw) -eq $receiptBeforeRepeat) "Repeated migration changed the existing receipt."
    Assert-True (@($repeat.results | Where-Object { $_.status -eq "moved" }).Count -eq 0) "Repeated migration moved an item twice."

    $releaseApply = Invoke-Migration -OutputClass artifacts -Apply
    Assert-True (@($releaseApply.results | Where-Object { $_.name -eq "old-release-output" -and $_.status -eq "moved" }).Count -eq 1) "Artifacts migration did not preserve the old release output."
    Assert-True (@($releaseApply.results | Where-Object { $_.name -eq "tuple" -and $_.status -eq "moved" }).Count -eq 1) "Artifacts migration did not preserve the tuple."
    $movedReleasePayload = Join-Path $sandboxRoot "acceptance-state\legacy-artifacts\old-release-output\package\runtime.bin"
    Assert-True ((Get-FileHash -LiteralPath $movedReleasePayload -Algorithm SHA256).Hash.ToLowerInvariant() -eq $releasePayloadHash) "Artifacts migration changed release content."
    $tupleRoot = Join-Path $sandboxRoot "acceptance-state\legacy-artifacts\tuple"
    $legacyArtifactTuplePlan = Invoke-AcceptancePlan $movedRoot
    Assert-True ([string]$legacyArtifactTuplePlan.credentialNamespace -eq $expectedNamespace) "Acceptance runner rejected a tuple under legacy-artifacts."
    $releaseReceipt = $null
    $releaseReceiptPath = $null
    foreach ($receiptFile in @(Get-ChildItem -LiteralPath (Join-Path $sandboxRoot "acceptance-state\migration-receipts") -Filter "*.json" -File)) {
        $candidateReceipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json
        if ($candidateReceipt.outputClass -eq "artifacts" -and $candidateReceipt.destinationPath -eq (Join-Path $sandboxRoot "acceptance-state\legacy-artifacts\old-release-output")) { $releaseReceipt = $candidateReceipt; $releaseReceiptPath = $receiptFile.FullName; break }
    }
    Assert-True ($null -ne $releaseReceipt -and $null -eq $releaseReceipt.originalCredentialNamespace -and -not $releaseReceipt.isAcceptanceRoot) "Artifacts receipt must not claim an acceptance credential namespace."
    $releaseReceiptBeforeRepeat = Get-Content -LiteralPath $releaseReceiptPath -Raw
    $releaseRepeat = Invoke-Migration -OutputClass artifacts -Apply
    Assert-True (@($releaseRepeat.results | Where-Object { $_.status -eq "moved" }).Count -eq 0) "Repeated artifacts migration moved an item twice."
    Assert-True ((Get-Content -LiteralPath $releaseReceiptPath -Raw) -eq $releaseReceiptBeforeRepeat) "Repeated artifacts migration changed the receipt."

    [ordered]@{
        status = "passed"
        checks = @("dry-run-no-writes", "executable-and-command-line-reference-matching", "build-and-artifact-content-preserved", "sha-manifests-and-counts", "credential-namespace-preserved", "tuple-in-legacy-artifacts", "missing-receipt-fails-closed", "containment-rejected", "reparse-attribute-guards-rejected", "repeat-idempotent")
    } | ConvertTo-Json -Depth 3
} finally {
    if ($null -ne $previousCimBody) {
        Set-Item -LiteralPath Function:\global:Get-CimInstance -Value $previousCimBody
    } else {
        Remove-Item -LiteralPath Function:\global:Get-CimInstance -Force -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name AcceptanceMigrationTestProcesses -Scope Global -ErrorAction SilentlyContinue
    $fullSandbox = [IO.Path]::GetFullPath($sandboxRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $fullArtifacts = [IO.Path]::GetFullPath($artifactsRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($fullSandbox.StartsWith($fullArtifacts, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $fullSandbox)) {
        $cleanupStack = [Collections.Generic.Stack[string]]::new()
        $cleanupStack.Push($fullSandbox)
        while ($cleanupStack.Count -gt 0) {
            foreach ($entry in @(Get-ChildItem -LiteralPath $cleanupStack.Pop() -Force)) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Refusing recursive test cleanup because the fixture contains a reparse point."
                }
                if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    $cleanupStack.Push($entry.FullName)
                }
            }
        }
        Remove-Item -LiteralPath $fullSandbox -Recurse -Force
    }
}
