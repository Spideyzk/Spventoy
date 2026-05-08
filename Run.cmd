@echo off
REM ============================================================================
REM  Run.cmd - Windows entry point for Spventoy
REM
REM  Default: launches the WPF GUI (Spventoy-GUI.ps1).
REM  If any arguments are passed, falls back to running the CLI directly.
REM
REM  Self-elevates to Administrator (Ventoy needs admin to write the USB) and
REM  bypasses PowerShell's ExecutionPolicy + Mark-of-the-Web.
REM ============================================================================
setlocal

REM --- Self-elevate to Administrator if needed ------------------------------
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

REM --- Pick GUI by default, CLI if any arg was passed -----------------------
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Spventoy-GUI.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-MultibootUSB.ps1" %*
    echo.
    pause
)
