@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\copy-game-settings.ps1" -Restore
pause
