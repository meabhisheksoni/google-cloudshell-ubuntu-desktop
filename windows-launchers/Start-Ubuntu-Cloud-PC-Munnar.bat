@echo off
title Ubuntu Cloud PC Launcher - MUNNAR
color 0B

echo ====================================================================
echo         Ubuntu Cloud PC - Server Activation [MUNNAR]
echo ====================================================================
echo.

:: 1. Isolate environment and fix account
set "ACCOUNT=munnartirupatitrip2@gmail.com"
set "CLOUDSDK_CORE_ACCOUNT=%ACCOUNT%"
set "APPDATA=C:\Users\Abhishek soni\AppData\Roaming"
set "DIRECT_URL=https://8080-cs-358858335060-default.cs-asia-southeast1-seal.cloudshell.dev/vnc.html?v=20261119c&autoconnect=true&resize=remote&authuser=0"
set "CHROME_PROFILE=Profile 33"

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

:: 3. Locate Chrome binary
set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

echo [1/3] Enforcing active Google account: %ACCOUNT%...
call "%GCLOUD%" config set account %ACCOUNT% --quiet

echo.
echo [2/3] Activating Ubuntu XFCE desktop services on Cloud Shell (MUNNAR)...
call "%GCLOUD%" cloud-shell ssh --account=%ACCOUNT% --command="bash ~/start-desktop.sh"
if %errorlevel% neq 0 (
    echo.
    echo ====================================================================
    echo  [ERROR] Cloud Shell desktop failed to start or verify on port 8080!
    echo ====================================================================
    echo Please inspect the error messages above.
    pause
    exit /b 1
)

echo.
echo ====================================================================
echo  SUCCESS: Munnar Ubuntu Cloud PC Server is RUNNING and VERIFIED!
echo ====================================================================
echo.
echo  Opening Ubuntu Cloud PC in your %ACCOUNT% Chrome profile (%CHROME_PROFILE%)...
if exist "%CHROME%" (
    start "" "%CHROME%" --profile-directory="%CHROME_PROFILE%" "%DIRECT_URL%"
) else (
    start "" "%DIRECT_URL%"
)
echo.
echo  Direct link (also opened automatically):
echo  %DIRECT_URL%
echo.
echo ====================================================================
echo.
echo [3/3] Connecting to interactive Cloud Shell terminal...
echo You can use this terminal to manage your cloud instance.
echo Close this window only when you want to stop working.
echo.
call "%GCLOUD%" cloud-shell ssh --account=%ACCOUNT%

echo.
echo Server session ended.
pause
