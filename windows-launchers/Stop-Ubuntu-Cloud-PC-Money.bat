@echo off
title Ubuntu Cloud PC - STOP Server [MONEY]
color 0C

echo ====================================================================
echo         Ubuntu Cloud PC - Server Shutdown [MONEY]
echo ====================================================================
echo.

:: 1. Isolate environment and fix account
set "ACCOUNT=money000000money@gmail.com"
set "CLOUDSDK_CORE_ACCOUNT=%ACCOUNT%"
set "APPDATA=C:\Users\Abhishek soni\AppData\Roaming"

:: 2. Locate gcloud binary
set "GCLOUD=C:\Users\Abhishek soni\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
if not exist "%GCLOUD%" set "GCLOUD=%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
if not exist "%GCLOUD%" (
    where gcloud >nul 2>&1
    if %errorlevel% equ 0 (
        set "GCLOUD=gcloud"
    ) else (
        echo [ERROR] Google Cloud SDK not found!
        echo Expected at: %GCLOUD%
        pause
        exit /b 1
    )
)

echo [1/2] Enforcing active Google account: %ACCOUNT%...
call "%GCLOUD%" config set account %ACCOUNT% --quiet

echo.
echo [2/2] Stopping all desktop services on Cloud Shell (MONEY)...
call "%GCLOUD%" cloud-shell ssh --account=%ACCOUNT% --command="supervisorctl -c ~/cloudshell-desktop-supervisor.conf stop all 2>/dev/null; pkill -9 -f supervisord 2>/dev/null; pkill -9 -f websockify 2>/dev/null; pkill -9 -f x11vnc 2>/dev/null; pkill -9 -f Xvfb 2>/dev/null; pkill -9 -f startxfce4 2>/dev/null; pkill -9 -f xfce4 2>/dev/null; rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 ~/supervisor.sock ~/supervisord.pid 2>/dev/null; echo '=== VERIFICATION: Checking port 8080 ==='; if curl -s -I http://127.0.0.1:8080/vnc.html 2>/dev/null | grep -q '200 OK'; then echo '[WARNING] Port 8080 still responding'; exit 1; else echo '[SUCCESS] Server is completely stopped and port 8080 is offline.'; fi"

if %errorlevel% equ 0 (
    echo.
    echo ====================================================================
    echo  SUCCESS: Money Cloud PC server has been cleanly SHUT DOWN.
    echo ====================================================================
    echo Port 8080 is offline and all background desktop processes are stopped.
) else (
    echo.
    echo ====================================================================
    echo  [NOTICE] Shutdown command executed. Check messages above.
    echo ====================================================================
)

echo.
pause
