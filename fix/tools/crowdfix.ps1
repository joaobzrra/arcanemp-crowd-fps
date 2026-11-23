# ArcaneMP crowd FPS fix: adds or removes r.SkeletalMeshLODBias in the ArcaneMP Engine.ini.
# Usage: crowdfix.ps1 -Bias 2        (install, strong)
#        crowdfix.ps1 -Bias 1        (install, mild)
#        crowdfix.ps1 -Remove        (uninstall)
#        -Path <file>                (optional: another Engine.ini, used for testing)
param(
    [ValidateRange(1, 3)][int]$Bias = 2,
    [switch]$Remove,
    [string]$Path = (Join-Path $env:LOCALAPPDATA 'Hogwarts Legacy\ArcaneMP\Saved\Config\WindowsNoEditor\Engine.ini')
)
$ErrorActionPreference = 'Stop'
$Key = 'r.SkeletalMeshLODBias'

if (Get-Process -Name 'HogwartsLegacy', 'ArcaneMPLauncher' -ErrorAction SilentlyContinue) {
    Write-Host 'Close Hogwarts Legacy first (the game rewrites this file when it exits). Nothing changed.' -ForegroundColor Yellow
    exit 1
}

$lines = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $Path) {
    $backup = "$Path.before-crowdfix"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $Path -Destination $backup }
    foreach ($l in [IO.File]::ReadAllLines($Path)) { $lines.Add($l) }
} elseif ($Remove) {
    Write-Host "No settings file found at $Path. Nothing to remove."
    exit 0
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
}

# Locate [SystemSettings] and the end of that section.
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq '[SystemSettings]') { $start = $i; break } }
$end = $lines.Count
if ($start -ge 0) {
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end = $i; break } }
    # Drop any existing value of our key inside the section.
    for ($i = $end - 1; $i -gt $start; $i--) {
        if ($lines[$i].Trim() -match ('^' + [regex]::Escape($Key) + '\s*=')) { $lines.RemoveAt($i); $end-- }
    }
}

if ($Remove) {
    if ($start -ge 0) {
        $hasOther = $false
        for ($i = $start + 1; $i -lt $end; $i++) { if ($lines[$i].Trim() -ne '') { $hasOther = $true; break } }
        if (-not $hasOther) { for ($i = $end - 1; $i -ge $start; $i--) { $lines.RemoveAt($i) } }
    }
    $msg = 'Crowd fix removed.'
} else {
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
        $lines.Add('[SystemSettings]')
        $start = $lines.Count - 1
    }
    $lines.Insert($start + 1, "$Key=$Bias")
    $msg = "Crowd fix installed ($Key=$Bias)."
}

$text = ($lines -join "`r`n") + "`r`n"
[IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host $msg -ForegroundColor Green
Write-Host "File: $Path"
