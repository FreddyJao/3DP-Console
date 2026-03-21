@echo off
REM Start 3DP-Console (interactive G-Code console)
REM "pause" haelt das Fenster offen, damit du Meldungen lesen kannst.
REM Ohne zweite Taste: Start-Console-NoPause.cmd oder direkt in PowerShell:
REM   powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\3DP-Console.ps1"
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\3DP-Console.ps1"
pause
