param(
    [Parameter(Mandatory)][string]$Ue4ss,      # UE4SS folder loaded in the game (the kit with CrowdDiag + CrowdInv)
    [Parameter(Mandatory)][string]$OutDir,
    [int]$Settle = 15,
    [int]$Measure = 40
)
# A-B test of the CrowdFix build staged as Mods\CrowdDiag\Scripts\crowdfix_main.lua. It runs inside CrowdDiag's Lua
# state (command `lua crowdfix_main.lua`) and reads Mods\CrowdDiag\settings.txt on every sweep, so each step only
# rewrites that file and measures. Steps: off, new far-interval only, off, shipped defaults, off.
$settings = Join-Path $Ue4ss 'Mods\CrowdDiag\settings.txt'
$cmd = Join-Path $Ue4ss 'Mods\CrowdDiag\cmd.txt'
$ulog = Join-Path $Ue4ss 'UE4SS.log'
$driver = Join-Path $PSScriptRoot 'live-ablate.ps1'
function Set-Fix([int]$enabled, [int]$uroDistance) {
    Set-Content -Path $settings -Encoding ascii -Value "enabled=$enabled", "distance=$uroDistance", 'interpolate=1', 'animrate=2', 'fardistance=5000', 'farinterval=0.2'
}
Set-Fix 0 2500
if (-not (Select-String -Path $ulog -Pattern '\[CrowdFix\] loaded' -Quiet)) {
    Set-Content -Path $cmd -Value 'lua crowdfix_main.lua' -Encoding ascii
    Start-Sleep -Seconds 6
}
"CrowdFix loaded in the game: $([bool](Select-String -Path $ulog -Pattern '\[CrowdFix\] loaded' -Quiet))"
$plan = @(
    @{ label = 'fix off 1'; enabled = 0; uro = 2500 },
    @{ label = 'far 5 Hz only'; enabled = 1; uro = 99999999 },
    @{ label = 'fix off 2'; enabled = 0; uro = 2500 },
    @{ label = 'shipped defaults'; enabled = 1; uro = 2500 },
    @{ label = 'fix off 3'; enabled = 0; uro = 2500 }
)
foreach ($p in $plan) {
    Set-Fix $p.enabled $p.uro
    & $driver -Ue4ss $Ue4ss -OutDir $OutDir -Settle $Settle -Measure $Measure -Steps ($p.label + '|') | Where-Object { $_ -notmatch '^results ->' }
    $last = Select-String -Path $ulog -Pattern '\[CrowdFix\] enabled=' | Select-Object -Last 1
    if ($last) { '    fix:  ' + ($last.Line -replace '^.*\[CrowdFix\] ', '') }
}
'--- CrowdFix check lines:'
Select-String -Path $ulog -Pattern '\[CrowdFix\] (far check|error|a\.URO)' | Select-Object -Last 6 | ForEach-Object { ($_.Line -replace '^.*\[CrowdFix\] ', '') }
