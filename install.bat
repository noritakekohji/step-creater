@echo off
setlocal EnableDelayedExpansion

rem ============================================================
rem  StepCreater Installer
rem
rem  - Copies StepCreater\ to %LOCALAPPDATA%\Programs\StepCreater
rem  - Creates a Start Menu shortcut
rem  - No admin rights required (per-user install)
rem ============================================================

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\StepCreater"
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
set "SHORTCUT=%START_MENU%\StepCreater.lnk"
set "SCRIPT_DIR=%~dp0"

echo.
echo ============================================================
echo  StepCreater Installer
echo ============================================================
echo.
echo  Install location : %INSTALL_DIR%
echo  Start Menu       : %SHORTCUT%
echo.

rem --- Check PowerShell availability ---------------------------
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] powershell.exe not found.
    echo         PowerShell 5.1 or later is required.
    pause
    exit /b 1
)

rem --- Check source folder -------------------------------------
if not exist "%SCRIPT_DIR%StepCreater\StepCreater.ps1" (
    echo [ERROR] Source folder not found:
    echo         %SCRIPT_DIR%StepCreater\
    echo         Run install.bat from the repository root.
    pause
    exit /b 1
)

rem --- Confirm with user ---------------------------------------
choice /C YN /M "Proceed with install"
if errorlevel 2 (
    echo Cancelled.
    pause
    exit /b 0
)

rem --- Copy files ----------------------------------------------
echo.
echo Copying files...
if exist "%INSTALL_DIR%" (
    echo  - removing existing install...
    rmdir /s /q "%INSTALL_DIR%"
)
mkdir "%INSTALL_DIR%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create install directory.
    pause
    exit /b 1
)
xcopy "%SCRIPT_DIR%StepCreater" "%INSTALL_DIR%\StepCreater\" /E /I /Q /Y >nul
if errorlevel 1 (
    echo [ERROR] Copy failed.
    pause
    exit /b 1
)
echo  - StepCreater\ copied.

rem --- Write launcher cmd --------------------------------------
> "%INSTALL_DIR%\StepCreater.cmd" echo @echo off
>>"%INSTALL_DIR%\StepCreater.cmd" echo powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%%~dp0StepCreater\StepCreater.ps1" %%*
echo  - StepCreater.cmd launcher created.

rem --- Create Start Menu shortcut via PowerShell ---------------
echo  - Creating Start Menu shortcut...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell;" ^
  "$s = $ws.CreateShortcut('%SHORTCUT%');" ^
  "$s.TargetPath = '%INSTALL_DIR%\StepCreater.cmd';" ^
  "$s.WorkingDirectory = '%INSTALL_DIR%';" ^
  "$s.Description = 'StepCreater - procedure document tool';" ^
  "$s.IconLocation = 'powershell.exe,0';" ^
  "$s.Save()" >nul 2>&1
if errorlevel 1 (
    echo [WARN] Could not create Start Menu shortcut, continuing anyway.
) else (
    echo  - Shortcut created.
)

echo.
echo ============================================================
echo  Install complete.
echo.
echo  Launch:  Start Menu -^> StepCreater
echo  Or run:  "%INSTALL_DIR%\StepCreater.cmd"
echo.
echo  To remove: run uninstall.bat from this repo.
echo ============================================================
echo.
pause
endlocal
