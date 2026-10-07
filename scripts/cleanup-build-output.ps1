[CmdletBinding()]
param([switch] $Apply)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'build-output-lifecycle.mjs'), 'cleanup')
if ($Apply) { $arguments += '--apply' }
& node @arguments
if ($LASTEXITCODE -ne 0) { throw 'Build cleanup failed closed. No process was terminated.' }
