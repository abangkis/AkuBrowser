# Shared Windows build producer adapter. The JSON registry is outside disposable output.
function Start-AkuOutput {
    param([string] $Family, [string[]] $Paths, [long] $ReserveBytes = 1073741824)
    $root = Split-Path -Parent $PSScriptRoot
    $classes = @($Paths | ForEach-Object {
        $absolute = [IO.Path]::GetFullPath($_)
        if ($absolute.StartsWith((Join-Path $root 'build') + '\', [StringComparison]::OrdinalIgnoreCase)) { 'build' }
        elseif ($absolute.StartsWith((Join-Path $root 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) { 'artifacts' }
        else { throw "Output must stay in AkuBrowser/build or artifacts: $absolute" }
    } | Select-Object -Unique)
    if ($classes.Count -ne 1) { throw 'One producer must use one output class.' }
    $encoded = ConvertTo-Json -InputObject @($Paths) -Compress
    # Windows PowerShell 5.1 strips JSON quotes when passing native arguments.
    # Base64 carries UTF-8 JSON intact in both legacy and modern PowerShell.
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($encoded))
    $text = & node (Join-Path $PSScriptRoot 'build-output-lifecycle.mjs') begin --family $Family --class $classes[0] --outputs-base64 $payload64 --reserve $ReserveBytes --owner-pid $PID
    if ($LASTEXITCODE -ne 0) { throw 'Output retention admission failed; runtime copy was not started.' }
    $admission = $text | Out-String | ConvertFrom-Json
    if ($admission.borrowed) { return 'borrowed:' + $admission.id }
    return $admission.id
}

function Complete-AkuOutput {
    param([string] $Id, [switch] $Failed, [switch] $Pin)
    if ($Id.StartsWith('borrowed:')) { return }
    $state = if ($Failed) { 'failed' } else { 'complete' }
    $arguments = @((Join-Path $PSScriptRoot 'build-output-lifecycle.mjs'), 'finish', '--id', $Id, '--state', $state)
    if ($Pin) { $arguments += '--pin' }
    $text = & node @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Output finalization failed; output was preserved for review.' }
    # Keep existing producer stdout contracts (some callers parse their JSON).
}
