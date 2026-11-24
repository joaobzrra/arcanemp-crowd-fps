# Copies the normal Hogwarts Legacy settings into the ArcaneMP settings folder, with frame generation off.
#
# ArcaneMP keeps its own settings (%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP\Saved), and some servers lock the
# in-game settings menu, so changes made in the normal game never reach ArcaneMP on their own.
# This copies GameUserSettings.ini and SavedUserOptions.sav (the .sav carries its own copy of the same settings
# text and wins over the .ini). Frame generation is switched off in both copies: ArcaneMP 1.15.1 crashes with it
# (see frame-generation/ in this repository). Engine.ini is not touched, so the crowd fix stays.
# Every run first backs up the ArcaneMP files to %LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP-settings-backups\<time>\.
#
# Usage: copy-game-settings.ps1             copy the normal game's settings into ArcaneMP
#        copy-game-settings.ps1 -Restore    put back the newest backup
#        -SaveId <folder name>              only needed when the game has several SaveGames folders
#        -Root <folder>                     another "Hogwarts Legacy" folder, used for testing
param(
    [switch]$Restore,
    [string]$SaveId,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'Hogwarts Legacy')
)
$ErrorActionPreference = 'Stop'
# One byte = one character, so every file is rewritten byte for byte except the lines this script changes.
$Latin1 = [Text.Encoding]::GetEncoding(28591)

function Stop-Script([string]$Message) {
    Write-Host "$Message Nothing changed." -ForegroundColor Yellow
    exit 1
}

if (Get-Process -Name 'HogwartsLegacy', 'ArcaneMPLauncher' -ErrorAction SilentlyContinue) {
    Stop-Script 'Close Hogwarts Legacy first (the game rewrites these files when it exits).'
}

$mainIni = Join-Path $Root 'Saved\Config\WindowsNoEditor\GameUserSettings.ini'
$mainSaves = Join-Path $Root 'Saved\SaveGames'
$mpIni = Join-Path $Root 'ArcaneMP\Saved\Config\WindowsNoEditor\GameUserSettings.ini'
$mpSaves = Join-Path $Root 'ArcaneMP\Saved\SaveGames'
$backupRoot = Join-Path $Root 'ArcaneMP-settings-backups'

# SavedUserOptions.sav is an Unreal save file. The settings live in one property, SettingsData: an array of bytes
# holding the same text as GameUserSettings.ini. Layout: name, type "ArrayProperty", 8-byte size (= count + 4),
# inner type "ByteProperty", one "no GUID" byte, 4-byte count, the text, then the end marker "None".
$SavMarker = [string][char]13 + "`0`0`0SettingsData`0" + [char]14 + "`0`0`0ArrayProperty`0"
$SavInner = [string][char]13 + "`0`0`0ByteProperty`0`0"
$SavEnd = [string][char]5 + "`0`0`0None`0"

function Read-SettingsSav([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    $s = $Latin1.GetString($b)
    $at = $s.IndexOf($SavMarker, [StringComparison]::Ordinal)
    if ($at -lt 0 -or $s.IndexOf($SavMarker, $at + 1, [StringComparison]::Ordinal) -ge 0) { throw 'SettingsData not found exactly once' }
    $sizeAt = $at + $SavMarker.Length
    if ($s.Substring($sizeAt + 8, $SavInner.Length) -ne $SavInner) { throw 'unexpected bytes after SettingsData' }
    $countAt = $sizeAt + 8 + $SavInner.Length
    $size = [BitConverter]::ToInt64($b, $sizeAt)
    $count = [BitConverter]::ToInt32($b, $countAt)
    $textAt = $countAt + 4
    if ($size -ne $count + 4 -or $textAt + $count + $SavEnd.Length -gt $b.Length) { throw 'size fields do not match' }
    if ($s.Substring($textAt + $count, $SavEnd.Length) -ne $SavEnd) { throw 'unexpected bytes after the settings text' }
    return @{ Head = $s.Substring(0, $sizeAt); Text = $s.Substring($textAt, $count); Tail = $s.Substring($textAt + $count) }
}

function Write-SettingsSav($Parts, [string]$Text, [string]$Path) {
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $w.Write($Latin1.GetBytes($Parts.Head))
    $w.Write([int64]($Text.Length + 4))
    $w.Write($Latin1.GetBytes($SavInner))
    $w.Write([int32]$Text.Length)
    $w.Write($Latin1.GetBytes($Text))
    $w.Write($Latin1.GetBytes($Parts.Tail))
    $w.Flush()
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
}

function Set-FrameGenerationOff([string]$Text) {
    $t = [regex]::Replace($Text, '(?m)^Nvidia(LatencyMode|FrameGeneration)=[^\r\n]*\r?\n', '')
    $t = [regex]::Replace($t, '(?m)^LatencyMode=[^\r\n]*', 'LatencyMode=Off')
    $t = [regex]::Replace($t, '(?m)^FrameGeneration=[^\r\n]*', 'FrameGeneration=(Mode=Off,NumFramesInterpolated=0,LocStr="Off")')
    $t = [regex]::Replace($t, '(?m)^r\.ChosenFrameGenProvider=[^\r\n]*', 'r.ChosenFrameGenProvider=None')
    return $t
}

function Test-FrameGenerationOn([string]$Text) {
    return [regex]::IsMatch($Text, '(?m)^(FrameGeneration=\((?!Mode=Off)|r\.ChosenFrameGenProvider=(?!None\r?$)|Nvidia(FrameGeneration|LatencyMode)=)')
}

function Clear-ReadOnly([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).IsReadOnly) {
        Set-ItemProperty -LiteralPath $Path -Name IsReadOnly -Value $false
        Write-Host "Removed the read-only flag from $Path"
    }
}

function Save-Backup([string]$Name, [string]$Id) {
    $dir = Join-Path $backupRoot $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -LiteralPath $mpIni -Destination (Join-Path $dir 'GameUserSettings.ini')
    $sav = Join-Path $mpSaves "$Id\SavedUserOptions.sav"
    if (Test-Path -LiteralPath $sav) { Copy-Item -LiteralPath $sav -Destination (Join-Path $dir 'SavedUserOptions.sav') }
    [IO.File]::WriteAllText((Join-Path $dir 'saveid.txt'), $Id)
    return $dir
}

if (-not (Test-Path -LiteralPath $mpIni)) { Stop-Script 'No ArcaneMP settings found. Start ArcaneMP once, then run this again.' }

if ($Restore) {
    $last = Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*-before-restore' } | Sort-Object Name | Select-Object -Last 1
    if (-not $last) { Stop-Script "No backup found in $backupRoot." }
    $id = ([IO.File]::ReadAllText((Join-Path $last.FullName 'saveid.txt'))).Trim()
    $mpSav = Join-Path $mpSaves "$id\SavedUserOptions.sav"
    $safe = Save-Backup ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-before-restore') $id
    Clear-ReadOnly $mpIni
    Clear-ReadOnly $mpSav
    Copy-Item -LiteralPath (Join-Path $last.FullName 'GameUserSettings.ini') -Destination $mpIni -Force
    $bkSav = Join-Path $last.FullName 'SavedUserOptions.sav'
    if (Test-Path -LiteralPath $bkSav) {
        Copy-Item -LiteralPath $bkSav -Destination $mpSav -Force
    } elseif (Test-Path -LiteralPath $mpSav) {
        # ArcaneMP had no saved options before the copy; the game creates the file again on its next start.
        Remove-Item -LiteralPath $mpSav
    }
    Write-Host "Restored the ArcaneMP settings from backup $($last.Name)." -ForegroundColor Green
    Write-Host "The settings you just replaced are in $safe"
    exit 0
}

if (-not (Test-Path -LiteralPath $mainIni)) { Stop-Script 'No settings found for the normal game. Start Hogwarts Legacy once without ArcaneMP.' }

if ($SaveId) {
    $id = $SaveId
} else {
    $ids = @(Get-ChildItem -LiteralPath $mainSaves -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SavedUserOptions.sav') } | ForEach-Object { $_.Name })
    if ($ids.Count -eq 0) { Stop-Script "No SavedUserOptions.sav in $mainSaves. Start the normal game once and change a setting." }
    if ($ids.Count -gt 1) { Stop-Script ('Several save folders found (' + ($ids -join ', ') + '). Run again with -SaveId <one of them>.') }
    $id = $ids[0]
}
$mainSav = Join-Path $mainSaves "$id\SavedUserOptions.sav"
$mpSav = Join-Path $mpSaves "$id\SavedUserOptions.sav"
if (-not (Test-Path -LiteralPath $mainSav)) { Stop-Script "No SavedUserOptions.sav in $mainSaves\$id." }

# Read and check everything before writing anything.
try { $parts = Read-SettingsSav $mainSav } catch { Stop-Script "The normal game's SavedUserOptions.sav has a layout this script does not know ($($_.Exception.Message))." }
$newSavText = Set-FrameGenerationOff $parts.Text
$newIni = Set-FrameGenerationOff ($Latin1.GetString([IO.File]::ReadAllBytes($mainIni)))
if ((Test-FrameGenerationOn $newIni) -or (Test-FrameGenerationOn $newSavText)) { Stop-Script 'Could not switch frame generation off in the copy.' }

$bk = Save-Backup (Get-Date -Format 'yyyyMMdd-HHmmss') $id
Clear-ReadOnly $mpIni
Clear-ReadOnly $mpSav
[IO.File]::WriteAllBytes($mpIni, $Latin1.GetBytes($newIni))
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mpSav) | Out-Null
Write-SettingsSav $parts $newSavText $mpSav

# Read both files back and check them.
$readIni = $Latin1.GetString([IO.File]::ReadAllBytes($mpIni))
$readSav = Read-SettingsSav $mpSav
if ($readIni -ne $newIni -or $readSav.Text -ne $newSavText -or (Test-FrameGenerationOn $readIni) -or (Test-FrameGenerationOn $readSav.Text)) {
    Write-Host "The files did not read back as written. Run this again with -Restore to put back $bk" -ForegroundColor Red
    exit 1
}

Write-Host 'Copied the normal game settings into ArcaneMP (frame generation off).' -ForegroundColor Green
Write-Host "Backup of the previous ArcaneMP settings: $bk"
Write-Host 'Settings now in ArcaneMP:'
$keys = 'ResolutionSizeX', 'ResolutionSizeY', 'FullscreenMode', 'UpscaleMode', 'FrameRateLimit', 'bUseVSync',
    'bEnableRaytracingReflections', 'bEnableRaytracingShadows', 'bEnableRaytracingAO',
    'sg.ViewDistanceQuality', 'sg.ShadowQuality', 'sg.TextureQuality', 'sg.PopulationQuality', 'FrameGeneration'
foreach ($k in $keys) {
    $m = [regex]::Match($newSavText, '(?m)^' + [regex]::Escape($k) + '=([^\r\n]*)')
    if ($m.Success) {
        $v = $m.Groups[1].Value
        if ($k -eq 'FrameRateLimit' -and $v -like '-1*') { $v += '  (no FPS cap)' }
        Write-Host ('  {0} = {1}' -f $k, $v)
    }
}
Write-Host 'Engine.ini was not touched.'
