@echo off
REM ============================================================================
REM  Build-Exe.cmd - Compile Spventoy-GUI.ps1 into Spventoy.exe
REM
REM  Requires the ps2exe module (auto-installs on first run).
REM  Output: Spventoy.exe (~100 KB) with embedded icon and UAC manifest.
REM ============================================================================
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "if (-not (Get-Module -ListAvailable -Name ps2exe)) { Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber }; ^
   Import-Module ps2exe; ^
   Invoke-PS2EXE -InputFile '%~dp0Spventoy-GUI.ps1' -OutputFile '%~dp0Spventoy.exe' -IconFile '%~dp0spventoy.ico' -Title 'Spventoy' -Description 'Multiboot USB Builder' -Company 'Spventoy' -Product 'Spventoy' -Version '1.0.0.0' -Copyright 'MIT License' -RequireAdmin -NoConsole -STA -SupportOS"

echo.
if exist "%~dp0Spventoy.exe" (
    for %%I in ("%~dp0Spventoy.exe") do echo Built Spventoy.exe ^(%%~zI bytes^)
) else (
    echo Build failed.
)
echo.
pause
