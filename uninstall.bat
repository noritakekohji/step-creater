@echo off
setlocal EnableDelayedExpansion

rem ============================================================
rem  StepCreater Uninstaller
rem
rem  - Removes %LOCALAPPDATA%\Programs\StepCreater
rem  - Removes the Start Menu shortcut
rem  - Optionally removes user config at %APPDATA%\StepCreater
rem ============================================================

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\StepCreater"
set "SHORTCUT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\StepCreater.lnk"
set "CONFIG_DIR=%APPDATA%\StepCreater"

echo.
echo ============================================================
echo  StepCreater Uninstaller
echo ============================================================
echo.
echo  Install location : %INSTALL_DIR%
echo  Start Menu       : %SHORTCUT%
echo  Config (optional): %CONFIG_DIR%
echo.

rem --- Confirm uninstall ---------------------------------------
choice /C YN /M "Proceed with uninstall"
if errorlevel 2 (
    echo Cancelled.
    pause
    exit /b 0
)

rem --- Remove install directory --------------------------------
if exist "%INSTALL_DIR%" (
    echo Removing %INSTALL_DIR%...
    rmdir /s /q "%INSTALL_DIR%"
    if errorlevel 1 (
        echo [WARN] Could not fully remove %INSTALL_DIR%.
    ) else (
        echo  - Removed.
    )
) else (
    echo  - Install directory not found, skipping.
)

rem --- Remove Start Menu shortcut ------------------------------
if exist "%SHORTCUT%" (
    echo Removing Start Menu shortcut...
    del /f /q "%SHORTCUT%" >nul 2>&1
    if errorlevel 1 (
        echo [WARN] Could not remove shortcut.
    ) else (
        echo  - Removed.
    )
) else (
    echo  - Shortcut not found, skipping.
)

rem --- Optionally remove user config ---------------------------
if exist "%CONFIG_DIR%" (
    echo.
    echo User config and workfolder history found at:
    echo   %CONFIG_DIR%
    choice /C YN /M "Remove this too (configuration will be lost)"
    if errorlevel 2 (
        echo  - Config preserved.
    ) else (
        rmdir /s /q "%CONFIG_DIR%"
        if errorlevel 1 (
            echo [WARN] Could not remove %CONFIG_DIR%.
        ) else (
            echo  - Config removed.
        )
    )
) else (
    echo  - No config directory to remove.
)

echo.
echo ============================================================
echo  Uninstall complete.
echo.
echo  Note: workfolders (your procedure docs) are NOT touched.
echo  They remain at whatever paths you created them under.
echo ============================================================
echo.
pause
endlocal
