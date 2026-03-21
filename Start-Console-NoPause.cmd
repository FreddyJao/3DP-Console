@echo off
REM Wie Start-Console.cmd, aber ohne "pause" am Ende (Fenster schliesst sofort nach Ende).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\3DP-Console.ps1"
