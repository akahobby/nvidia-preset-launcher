@echo off
setlocal EnableExtensions
title NVIDIA Preset Launcher v1.0

set "VERSION=1.0"
set "AUTHOR=akahobby"

:: Purple text on black background
color 0D

:: ==============================
:: UAC AUTO ELEVATION (Admin)
:: ==============================
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    cls
    echo ============================================
    echo   NVIDIA PRESET LAUNCHER v%VERSION%  ^|  %AUTHOR%
    echo ============================================
    echo.
    echo   Requesting Administrator permission...
    echo.
    echo ============================================
    echo.
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B
)
if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs" >nul 2>&1

:: GitHub RAW links
set "URL_50=https://raw.githubusercontent.com/akahobby/nvidia-preset-launcher/main/Nvidia-Preset-50.ps1"
set "URL_M=https://raw.githubusercontent.com/akahobby/nvidia-preset-launcher/main/Nvidia-Preset-M.ps1"
set "URL_K=https://raw.githubusercontent.com/akahobby/nvidia-preset-launcher/main/Nvidia-Preset-K.ps1"
set "URL_NP=https://raw.githubusercontent.com/akahobby/nvidia-preset-launcher/main/Nvidia-Preset-NP.ps1"

:menu
cls
echo ============================================
echo   NVIDIA PRESET LAUNCHER v%VERSION%  ^|  %AUTHOR%
echo ============================================
echo.
echo   Select your GPU generation:
echo.
echo   [1]  Preset 50  - RTX 50 Series (Dynamic MFG)
echo   [2]  Preset M   - RTX 40 Series
echo   [3]  Preset K   - RTX 20 / 30 Series
echo   [4]  Preset NP  - No DLSS preset
echo   [5]  Exit
echo.
echo ============================================
echo.
set /p choice=Select option (1-5): 

if "%choice%"=="1" goto RUN_50
if "%choice%"=="2" goto RUN_M
if "%choice%"=="3" goto RUN_K
if "%choice%"=="4" goto RUN_NP
if "%choice%"=="5" exit
goto menu

:RUN_50
cls
echo ============================================
echo   Applying Preset 50...
echo ============================================
echo.
set "PS1=%TEMP%\preset_50.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL_50%' -OutFile '%PS1%'; Unblock-File '%PS1%'; & '%PS1%'" || (
    echo.
    echo   Failed to download/run Preset 50.
    echo.
    pause
    exit /b 1
)
exit

:RUN_M
cls
echo ============================================
echo   Applying Preset M...
echo ============================================
echo.
set "PS1=%TEMP%\preset_M.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL_M%' -OutFile '%PS1%'; Unblock-File '%PS1%'; & '%PS1%'" || (
    echo.
    echo   Failed to download/run Preset M.
    echo.
    pause
    exit /b 1
)
exit

:RUN_K
cls
echo ============================================
echo   Applying Preset K...
echo ============================================
echo.
set "PS1=%TEMP%\preset_K.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL_K%' -OutFile '%PS1%'; Unblock-File '%PS1%'; & '%PS1%'" || (
    echo.
    echo   Failed to download/run Preset K.
    echo.
    pause
    exit /b 1
)
exit

:RUN_NP
cls
echo ============================================
echo   Applying Preset NP (No DLSS preset)...
echo ============================================
echo.
set "PS1=%TEMP%\preset_NP.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL_NP%' -OutFile '%PS1%'; Unblock-File '%PS1%'; & '%PS1%'" || (
    echo.
    echo   Failed to download/run Preset NP.
    echo.
    pause
    exit /b 1
)
exit
