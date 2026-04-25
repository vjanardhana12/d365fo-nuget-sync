@echo off
REM Double-click launcher for Sync-D365FONuGet.ps1
REM chcp 65001 = switch cmd.exe to UTF-8 so the Unicode box-drawing chars render correctly
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-D365FONuGet.ps1" %*
pause
