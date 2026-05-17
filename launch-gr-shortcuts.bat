@echo off
setlocal

set "ROOT=%~dp0"
set "AHK="

if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK if exist "%ProgramFiles%\AutoHotkey\AutoHotkey64.exe" set "AHK=%ProgramFiles%\AutoHotkey\AutoHotkey64.exe"
if not defined AHK if exist "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK=%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"

if not defined AHK (
  echo AutoHotkey v2 was not found.
  echo Run setup.ps1 first, or install AutoHotkey v2 manually.
  pause
  exit /b 1
)

start "" "%AHK%" "%ROOT%src\gr-shortcuts.ahk"

