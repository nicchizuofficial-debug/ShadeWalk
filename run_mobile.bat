@echo off
rem ShadeWalk - serve to your phone over the same Wi-Fi
cd /d "%~dp0"

echo ============================================
echo   ShadeWalk : open on your phone (same Wi-Fi)
echo ============================================
echo.
echo This PC IPv4 address(es):
ipconfig | findstr /i "IPv4"
echo.
echo On your phone's browser, open:   http://(the IPv4 above):8080
echo (PC and phone must be on the same Wi-Fi)
echo Press Ctrl+C in this window to stop.
echo.

echo Freeing port 8080 if it is already in use (old server)...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":8080" ^| findstr "LISTENING"') do taskkill /F /PID %%p >nul 2>&1
echo.
echo Getting packages (first run downloads new dependencies)...
call "C:\src\flutter\bin\flutter.bat" pub get
echo.

call "C:\src\flutter\bin\flutter.bat" run -d web-server --web-hostname=0.0.0.0 --web-port=8080

echo.
echo === Server stopped. You can close this window. ===
pause
