@echo off
setlocal
cd /d "%~dp0"
rem Launch the RDS deployment GUI with administrator privileges.
rem Falls back to running python directly if elevation is not possible.

if not exist "gui.py" (
    echo [ERROR] gui.py not found in current folder.
    pause
    exit /b 1
)

echo Launching RDS Deployment GUI with administrator privileges...
powershell -NoProfile -Command "Start-Process -FilePath 'python' -ArgumentList 'gui.py' -WorkingDirectory '%~dp0' -Verb RunAs"

endlocal
