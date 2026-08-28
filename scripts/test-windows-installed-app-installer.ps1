[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $TupleDirectory,
    [string] $InstallerPath = ""
)

$ErrorActionPreference = "Stop"
$browserRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $PSScriptRoot "build-windows-installed-app-installer.ps1"
$nsisSource = Join-Path $browserRoot "installer\windows\installed-app.nsi"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($builder, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) "Installed-app installer builder has PowerShell parse errors."

$source = Get-Content -LiteralPath $nsisSource -Raw
$launcherIndex = $source.IndexOf('File /oname=AkuBrowserLauncher.exe')
$versionIndex = $source.IndexOf('File /r "${PAYLOAD_ROOT}\runtime\versions\${APP_VERSION}\*"')
$manifestIndex = $source.IndexOf('File /oname=install-manifest.json')
$currentIndex = $source.IndexOf('File /oname=current.json')
Assert-True ($launcherIndex -ge 0 -and $versionIndex -gt $launcherIndex -and $manifestIndex -gt $versionIndex -and $currentIndex -gt $manifestIndex) "NSIS source does not activate the complete tuple in the required order."
Assert-True ($source.Contains('CreateShortcut "$SMPROGRAMS\AkuBrowser\AkuBrowser.lnk" "$INSTDIR\AkuBrowserLauncher.exe"')) "NSIS source does not create the launcher shortcut."
Assert-True (-not $source.Contains('NativeMessagingHosts')) "Installed-app NSIS source must not register the transitional Native Messaging host."
Assert-True (-not $source.Contains('taskkill.exe')) "Installed-app NSIS source must not forcibly terminate AkuBrowser processes."
Assert-True ($source.Contains('RMDir /r /REBOOTOK "$INSTDIR\runtime"')) "Uninstaller does not own the installed runtime tree."
Assert-True ($source.Contains('RMDir /r /REBOOTOK "$LOCALAPPDATA\AkuBrowser\browser-profile"')) "Explicit full reset does not cover the isolated browser profile."

$verification = & $builder -TupleDirectory $TupleDirectory -VerifyOnly | Out-String
if ($LASTEXITCODE -ne 0) { throw "Installed-app installer verification failed." }
$plan = $verification | ConvertFrom-Json
Assert-True ($plan.status -eq "verified" -and $plan.trustState -eq "unsigned" -and $plan.releaseReady -eq $true) "Installer verification reported an unexpected trust state."

if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
    Assert-True (Test-Path -LiteralPath $InstallerPath -PathType Leaf) "Compiled installer was not found: $InstallerPath"
    $bytes = [IO.File]::ReadAllBytes($InstallerPath)
    Assert-True ($bytes.Length -gt 1024 -and $bytes[0] -eq 0x4d -and $bytes[1] -eq 0x5a) "Compiled installer is not a bounded Windows PE artifact."
}

[ordered]@{
    status = "ok"
    version = [string]$plan.version
    tupleDirectory = [IO.Path]::GetFullPath($TupleDirectory)
    installerPath = if ([string]::IsNullOrWhiteSpace($InstallerPath)) { $null } else { $InstallerPath }
    trustState = "unsigned"
    releaseReady = $true
} | ConvertTo-Json -Depth 4
