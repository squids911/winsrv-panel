@echo off
setlocal
cd /d "%~dp0"

rem Build WinSrvPanel.exe (one-file, no console) with PyInstaller.
rem Requires:  pip install pyinstaller
rem The defaults are compiled INTO the exe (module schemas). User changes are
rem stored in the Windows registry (HKCU\Software\WinSrvPanel). No config.ini
rem is created next to the exe. roles.json is embedded; if one exists next to
rem the exe it is used as an override.

echo Checking PyInstaller...
python -m PyInstaller --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PyInstaller is not installed.
    echo         Install it first:  pip install pyinstaller
    pause
    exit /b 1
)

echo Building WinSrvPanel.exe ...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name WinSrvPanel ^
  --add-data "modules;modules" ^
  --add-data "roles.json;." ^
  gui.py

if errorlevel 1 (
    echo.
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

echo.
echo Done. Executable:  dist\WinSrvPanel.exe
echo Settings are stored in registry HKCU\Software\WinSrvPanel (not in files).
pause
