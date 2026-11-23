@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\crowdfix.ps1" -Bias 1
pause
