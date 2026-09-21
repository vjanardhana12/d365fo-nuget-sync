@echo off
title D365 F^&O NuGet Sync
REM ==============================================================
REM  RECOMMENDED WAY TO RUN - just double-click this file.
REM  It launches Sync-D365FONuGet.ps1 with no install and no
REM  PowerShell setup, and works even where .exe files are blocked.
REM  (chcp 65001 switches cmd.exe to UTF-8 so the box-drawing
REM   characters render correctly.)
REM ==============================================================
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-D365FONuGet.ps1" %*
pause
