# Builds dist\arcanemp-crowd-fix.zip, the player download on Releases, from fix\ and settings-copy\.
# All files sit at the root of the ZIP, with the PowerShell scripts in tools\.
# .bat and .txt files are written with CRLF line endings so cmd.exe and Notepad read them correctly.
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$files = [ordered]@{
    'LEIA-ME_README.txt'           = 'fix\LEIA-ME_README.txt'
    'install.bat'                  = 'fix\install.bat'
    'install-mild.bat'             = 'fix\install-mild.bat'
    'uninstall.bat'                = 'fix\uninstall.bat'
    'tools\crowdfix.ps1'           = 'fix\tools\crowdfix.ps1'
    'copy-settings.bat'            = 'settings-copy\copy-settings.bat'
    'restore-settings.bat'         = 'settings-copy\restore-settings.bat'
    'tools\copy-game-settings.ps1' = 'settings-copy\tools\copy-game-settings.ps1'
}
$dist = Join-Path $repo 'dist'
$stage = Join-Path $dist 'fix-stage'
$zip = Join-Path $dist 'arcanemp-crowd-fix.zip'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
foreach ($name in $files.Keys) {
    $dst = Join-Path $stage $name
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    $bytes = [IO.File]::ReadAllBytes((Join-Path $repo $files[$name]))
    if ($name -match '\.(bat|txt)$') {
        $t = [Text.Encoding]::UTF8.GetString($bytes) -replace "`r?`n", "`r`n"
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($t)
    }
    [IO.File]::WriteAllBytes($dst, $bytes)
}
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Remove-Item -LiteralPath $stage -Recurse -Force
[IO.Compression.ZipFile]::OpenRead($zip).Entries | ForEach-Object { '{0,-30} {1,6}' -f $_.FullName, $_.Length }
'{0} ({1} bytes)' -f $zip, (Get-Item -LiteralPath $zip).Length
