param(
    [Parameter(Mandatory)][string]$Ue4ss,      # UE4SS folder loaded in the game (the kit with CrowdDiag + CrowdInv)
    [Parameter(Mandatory)][string]$Settings,   # settings.txt the loaded CrowdFix build reads
    [Parameter(Mandatory)][string]$OutDir,
    [Parameter(Mandatory)][string[]]$On,       # one ON step each: "label|key=value;key=value" (keys of settings.txt)
    [int]$Settle = 12,
    [int]$Measure = 40
)
# Generic A-B for CrowdFix settings on a live server: OFF, then every ON step followed by OFF, so each ON step sits
# between two baselines. An ON step starts from "everything off" (URO out of range, no far interval, no sleep, no
# shadow or cloth change) plus the keys it names. Settings only: it never loads code. It ends OFF.
$ulog = Join-Path $Ue4ss 'UE4SS.log'
$driver = Join-Path $PSScriptRoot 'live-ablate.ps1'
if (@(Select-String -Path $ulog -Pattern '\[CrowdFix\] loaded').Count -ne 1) { throw 'expected exactly one CrowdFix instance loaded in this game' }
function Set-Fix([hashtable]$over) {
    $s = [ordered]@{ enabled = 1; distance = 99999999; interpolate = 1; animrate = 0; shadows = 0; cloth = 0; fardistance = 5000; farinterval = 0; sleepdistance = 0 }
    foreach ($k in $over.Keys) { $s[$k] = $over[$k] }
    Set-Content -Path $Settings -Encoding ascii -Value ($s.Keys | ForEach-Object { "$_=$($s[$_])" })
}
function Step([string]$label, [hashtable]$over) {
    Set-Fix $over
    $umark = (Get-Item $ulog).Length
    & $driver -Ue4ss $Ue4ss -OutDir $OutDir -Settle $Settle -Measure $Measure -Steps ($label + '|') | Where-Object { $_ -notmatch '^results ->' }
    $fs = [IO.File]::Open($ulog, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($umark, 'Begin'); $new = (New-Object IO.StreamReader($fs)).ReadToEnd() -split "`r?`n"; $fs.Dispose()
    $st = @($new | Where-Object { $_ -match '\[CrowdFix\] enabled=' })
    if ($st.Count) { '    fix:  ' + ($st[-1] -replace '^.*\[CrowdFix\] ', '') }
    $err = @($new | Where-Object { $_ -match '\[CrowdFix\] error' }); if ($err.Count) { "    ADD-ON ERRORS: $($err.Count); first: " + ($err[0] -replace '^.*\[CrowdFix\] ', '') }
}
$n = 0
Step "off $n" @{ enabled = 0 }
foreach ($o in $On) {
    $label, $kv = $o -split '\|', 2
    $over = @{}
    foreach ($pair in ($kv -split ';')) { $k, $v = $pair -split '=', 2; if ($k) { $over[$k.Trim()] = $v.Trim() } }
    Step $label $over
    $n++
    Step "off $n" @{ enabled = 0 }
}
Set-Fix @{ enabled = 0 }
'--- check lines:'
Select-String -Path $ulog -Pattern '\[CrowdFix\] (shadow check|cloth check|far check|sleep check|error)' | Select-Object -Last 5 | ForEach-Object { ($_.Line -replace '^.*\[CrowdFix\] ', '') }
"{0:HH:mm:ss} left OFF" -f (Get-Date)
