#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $BrowserRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet("build", "artifacts")]
    [string] $OutputClass = "build",
    [switch] $Apply
)

$ErrorActionPreference = "Stop"

function Get-FullPath([string] $Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathWithin([string] $Path, [string] $Root) {
    $fullPath = Get-FullPath $Path
    $fullRoot = Get-FullPath $Root
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparseAttributes([IO.FileAttributes] $Attributes, [string] $Description) {
    if (($Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must not be a reparse point."
    }
}

function Assert-NoReparseAncestors([string] $Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPath = [IO.Path]::GetPathRoot($fullPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $cursor = Get-FullPath $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            Assert-NoReparseAttributes $item.Attributes "A path component"
        }
        if ($cursor.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $next = $parent.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        if ($next.Equals($cursor, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $next
    }
}

function Get-Sha256Text([string] $Value) {
    $bytes = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))
    return [Convert]::ToHexString($bytes).ToLowerInvariant()
}

function Get-CredentialNamespace([string] $Path) {
    $digest = Get-Sha256Text $Path.ToLowerInvariant()
    return "AkuBrowserTest-" + $digest.Substring(0, 16)
}

function Get-ContentManifest([string] $ItemPath) {
    $fullItem = Get-FullPath $ItemPath
    Assert-NoReparseAncestors $fullItem
    $item = Get-Item -LiteralPath $fullItem -Force
    Assert-NoReparseAttributes $item.Attributes "The item itself"

    $entries = [Collections.Generic.List[object]]::new()
    [long]$byteCount = 0
    [long]$fileCount = 0
    [long]$directoryCount = 0

    if (($item.Attributes -band [IO.FileAttributes]::Directory) -eq 0) {
        $hash = (Get-FileHash -LiteralPath $fullItem -Algorithm SHA256).Hash.ToLowerInvariant()
        $length = [long](Get-Item -LiteralPath $fullItem -Force).Length
        $entries.Add([ordered]@{ path = "."; type = "file"; length = $length; sha256 = $hash })
        $byteCount = $length
        $fileCount = 1
    } else {
        $entries.Add([ordered]@{ path = "."; type = "directory"; length = 0; sha256 = $null })
        $directoryCount = 1
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($fullItem)
        $rootPrefix = $fullItem.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

        while ($pending.Count -gt 0) {
            $current = $pending.Pop()
            foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
                Assert-NoReparseAttributes $child.Attributes "A nested item"
                $relativePath = $child.FullName.Substring($rootPrefix.Length).Replace([IO.Path]::DirectorySeparatorChar, "/")
                if (($child.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    $entries.Add([ordered]@{ path = $relativePath; type = "directory"; length = 0; sha256 = $null })
                    $directoryCount++
                    $pending.Push($child.FullName)
                } else {
                    $hash = (Get-FileHash -LiteralPath $child.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    $length = [long]$child.Length
                    $entries.Add([ordered]@{ path = $relativePath; type = "file"; length = $length; sha256 = $hash })
                    $byteCount += $length
                    $fileCount++
                }
            }
        }
    }

    $orderedEntries = @($entries | Sort-Object -Property path, type)
    return [ordered]@{
        byteCount = $byteCount
        fileCount = $fileCount
        directoryCount = $directoryCount
        manifest = $orderedEntries
    }
}

function Get-ProcessSnapshot {
    try {
        $rows = @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath, CommandLine -ErrorAction Stop)
        return [pscustomobject]@{ available = $true; rows = $rows; errorType = $null }
    } catch {
        return [pscustomobject]@{ available = $false; rows = @(); errorType = $_.Exception.GetType().Name }
    }
}

function Test-ProcessReferencesPath($Snapshot, [string] $CandidatePath, [bool] $IsDirectory) {
    if (-not $Snapshot.available) { return $true }
    $candidate = (Get-FullPath $CandidatePath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidatePrefix = $candidate + [IO.Path]::DirectorySeparatorChar
    $pattern = [regex]::Escape($candidate) + '(?:[\\/]|["''\s]|$)'

    foreach ($process in $Snapshot.rows) {
        $executablePath = [string]$process.ExecutablePath
        if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
            try {
                $fullExecutable = Get-FullPath $executablePath
                if ($fullExecutable.Equals($candidate, [StringComparison]::OrdinalIgnoreCase) -or
                    ($IsDirectory -and $fullExecutable.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase))) {
                    return $true
                }
            } catch {
                # Malformed or device-style executable paths are ignored; command-line matching remains available.
            }
        }

        $commandLine = [string]$process.CommandLine
        if (-not [string]::IsNullOrWhiteSpace($commandLine) -and
            [regex]::IsMatch($commandLine.Replace("/", "\"), $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Write-Receipt([string] $Path, $Receipt, [switch] $Replace) {
    $temporaryPath = $Path + "." + [Guid]::NewGuid().ToString("N") + ".tmp"
    $json = $Receipt | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
    try {
        if ($Replace) {
            [IO.File]::Move($temporaryPath, $Path, $true)
        } else {
            [IO.File]::Move($temporaryPath, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$browserRoot = Get-FullPath $BrowserRoot
$sourceRootName = $OutputClass
$sourceRoot = Get-FullPath (Join-Path $browserRoot $sourceRootName)
$stateRoot = Get-FullPath (Join-Path $browserRoot "acceptance-state")
$legacyRootName = "legacy-" + $OutputClass
$legacyRoot = Get-FullPath (Join-Path $stateRoot $legacyRootName)
$receiptsRoot = Get-FullPath (Join-Path $stateRoot "migration-receipts")

Assert-NoReparseAncestors $browserRoot
Assert-NoReparseAncestors $sourceRoot
Assert-NoReparseAncestors $stateRoot
Assert-NoReparseAncestors $legacyRoot
Assert-NoReparseAncestors $receiptsRoot
if (-not (Test-Path -LiteralPath $browserRoot -PathType Container)) {
    throw "BrowserRoot must be an existing directory."
}
foreach ($managedRoot in @($sourceRoot, $stateRoot, $legacyRoot, $receiptsRoot)) {
    if ((Test-Path -LiteralPath $managedRoot) -and -not (Test-Path -LiteralPath $managedRoot -PathType Container)) {
        throw "A migration path exists but is not a directory: $managedRoot"
    }
}
if (-not (Test-PathWithin $sourceRoot $browserRoot) -or
    -not (Test-PathWithin $legacyRoot $stateRoot) -or
    -not (Test-PathWithin $receiptsRoot $stateRoot)) {
    throw "A migration path escapes its expected root."
}
$items = @()
if (Test-Path -LiteralPath $sourceRoot -PathType Container) {
    $items = @(Get-ChildItem -LiteralPath $sourceRoot -Force -ErrorAction Stop | Sort-Object -Property Name)
}

$processSnapshot = Get-ProcessSnapshot
$results = [Collections.Generic.List[object]]::new()
$timestamp = [DateTime]::UtcNow.ToString("o")

foreach ($item in $items) {
    $sourcePath = Get-FullPath $item.FullName
    $destinationPath = Get-FullPath (Join-Path $legacyRoot $item.Name)
    $sourceParent = Get-FullPath (Split-Path -Parent $sourcePath)
    $status = "planned"
    $reason = $null
    $manifestData = $null
    $isDirectory = (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0)

    if (-not $sourceParent.Equals($sourceRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-PathWithin $sourcePath $sourceRoot) -or
        -not $destinationPath.Equals((Get-FullPath (Join-Path $legacyRoot $item.Name)), [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-PathWithin $destinationPath $stateRoot)) {
        $status = "blocked-path-validation"
        $reason = "path-validation-failed"
    } elseif (Test-Path -LiteralPath $destinationPath) {
        $status = "blocked-destination-exists"
        $reason = "destination-exists"
    } elseif (-not $processSnapshot.available -or (Test-ProcessReferencesPath $processSnapshot $sourcePath $isDirectory)) {
        $status = "blocked-active-or-process-scan-unavailable"
        $reason = if ($processSnapshot.available) { "active-process-reference" } else { "process-scan-unavailable" }
    } else {
        try {
            $manifestData = Get-ContentManifest $sourcePath
        } catch {
            $status = "blocked-content-scan"
            $reason = $_.Exception.GetType().Name
        }
    }

    $isAcceptanceRoot = $false
    $originalCredentialNamespace = $null
    if ($OutputClass -eq "build" -and $isDirectory -and (Test-Path -LiteralPath (Join-Path $sourcePath "LocalAppData"))) {
        $isAcceptanceRoot = $true
        $originalCredentialNamespace = Get-CredentialNamespace $sourcePath
    }

    $receiptKey = Get-Sha256Text $destinationPath.ToLowerInvariant()
    $receiptPath = Join-Path $receiptsRoot ($OutputClass + "-" + $receiptKey + ".json")
    if ($status -eq "planned" -and (Test-Path -LiteralPath $receiptPath)) {
        $status = "blocked-receipt-exists"
        $reason = "receipt-exists"
    }

    if ($status -eq "planned" -and $Apply) {
        try {
            New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $receiptsRoot -Force | Out-Null
            Assert-NoReparseAncestors $sourcePath
            Assert-NoReparseAncestors $destinationPath
            Assert-NoReparseAncestors $receiptsRoot
            if (-not (Test-PathWithin $sourcePath $sourceRoot) -or
                -not (Test-PathWithin $destinationPath $legacyRoot) -or
                (Test-Path -LiteralPath $destinationPath) -or
                (Test-Path -LiteralPath $receiptPath)) {
                throw "A migration path changed or became occupied before the move."
            }
            $freshProcesses = Get-ProcessSnapshot
            if (-not $freshProcesses.available -or (Test-ProcessReferencesPath $freshProcesses $sourcePath $isDirectory)) {
                $status = "blocked-active-or-process-scan-unavailable"
                $reason = if ($freshProcesses.available) { "active-process-reference" } else { "process-scan-unavailable" }
            } else {
                $receipt = [ordered]@{
                    schemaVersion = 1
                    status = "prepared"
                    createdAtUtc = $timestamp
                    outputClass = $OutputClass
                    originalPath = $sourcePath
                    destinationPath = $destinationPath
                    itemName = $item.Name
                    byteCount = $manifestData.byteCount
                    fileCount = $manifestData.fileCount
                    directoryCount = $manifestData.directoryCount
                    isAcceptanceRoot = $isAcceptanceRoot
                    originalCredentialNamespace = $originalCredentialNamespace
                    manifest = $manifestData.manifest
                }
                Write-Receipt $receiptPath $receipt

                try {
                    if ($isDirectory) {
                        [IO.Directory]::Move($sourcePath, $destinationPath)
                    } else {
                        [IO.File]::Move($sourcePath, $destinationPath)
                    }
                } catch {
                    $receipt.status = "blocked-move"
                    $receipt.moveErrorType = $_.Exception.GetType().Name
                    Write-Receipt $receiptPath $receipt -Replace
                    $status = "blocked-move"
                    $reason = $receipt.moveErrorType
                }

                if ($status -eq "planned") {
                    try {
                        $destinationManifest = Get-ContentManifest $destinationPath
                        $expectedJson = ConvertTo-Json -InputObject @($manifestData.manifest) -Depth 8 -Compress
                        $actualJson = ConvertTo-Json -InputObject @($destinationManifest.manifest) -Depth 8 -Compress
                        if ($manifestData.byteCount -ne $destinationManifest.byteCount -or
                            $manifestData.fileCount -ne $destinationManifest.fileCount -or
                            $manifestData.directoryCount -ne $destinationManifest.directoryCount -or
                            $expectedJson -cne $actualJson) {
                            $receipt.status = "moved-verification-failed"
                            $receipt.completedAtUtc = [DateTime]::UtcNow.ToString("o")
                            Write-Receipt $receiptPath $receipt -Replace
                            $status = "moved-verification-failed"
                            $reason = "destination-manifest-mismatch"
                        } else {
                            $receipt.status = "moved"
                            $receipt.completedAtUtc = [DateTime]::UtcNow.ToString("o")
                            Write-Receipt $receiptPath $receipt -Replace
                            $status = "moved"
                            $reason = $null
                        }
                    } catch {
                        $receipt.status = "moved-verification-failed"
                        $receipt.completedAtUtc = [DateTime]::UtcNow.ToString("o")
                        $receipt.verificationErrorType = $_.Exception.GetType().Name
                        try { Write-Receipt $receiptPath $receipt -Replace } catch { }
                        $status = "moved-verification-failed"
                        $reason = $receipt.verificationErrorType
                    }
                }
            }
        } catch {
            if ($status -eq "planned") {
                $status = "blocked-move"
                $reason = $_.Exception.GetType().Name
            }
        }
    }

    $results.Add([ordered]@{
        name = $item.Name
        originalPath = $sourcePath
        destinationPath = $destinationPath
        status = $status
        reason = $reason
        byteCount = if ($null -ne $manifestData) { $manifestData.byteCount } else { $null }
        fileCount = if ($null -ne $manifestData) { $manifestData.fileCount } else { $null }
        isAcceptanceRoot = $isAcceptanceRoot
        credentialNamespace = $originalCredentialNamespace
    })
}

[ordered]@{
    mode = if ($Apply) { "apply" } else { "dry-run" }
    outputClass = $OutputClass
    browserRoot = $browserRoot
    sourceRoot = $sourceRoot
    stateRoot = $stateRoot
    processScanAvailable = $processSnapshot.available
    processScanErrorType = $processSnapshot.errorType
    itemCount = $items.Count
    results = @($results)
} | ConvertTo-Json -Depth 5
