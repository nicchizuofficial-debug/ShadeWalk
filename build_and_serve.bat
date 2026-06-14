@echo off
cd /d "%~dp0"

echo.
echo === [1/3] Building Flutter Web ===
call C:\src\flutter\bin\flutter.bat build web --release
echo Build exitcode: %errorlevel%
if %errorlevel% neq 0 (
    echo BUILD FAILED - see errors above
    pause
    exit /b 1
)

echo.
echo === [2/3] Starting server ===
start "ShadeWalk Server" cmd /c "C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\serve_web.dart & pause"
echo Waiting for server...
timeout /t 4 /nobreak

echo.
echo === [3/3] Opening Chrome ===
set CHROME=
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" set CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe
if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" set CHROME=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe

if "%CHROME%"=="" (
    echo Chrome not found - open http://127.0.0.1:8080 manually
) else (
    start "" "%CHROME%" --app=http://127.0.0.1:8080 --window-size=390,844 --window-position=200,50
    echo Chrome launched.
)

echo.
echo Done. Close "ShadeWalk Server" window to stop the server.
pause
