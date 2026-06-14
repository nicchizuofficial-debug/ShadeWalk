@echo off
rem ShadeWalk - open the app in a phone-sized window on THIS PC (Chrome app mode)
cd /d "%~dp0"
set "FL=C:\src\flutter\bin\flutter.bat"
set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"

echo Freeing port 8080 if it is already in use (old server)...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":8080" ^| findstr "LISTENING"') do taskkill /F /PID %%p >nul 2>&1
echo.
echo Getting packages (first run downloads new dependencies)...
call "%FL%" pub get
echo.
echo Starting local web server in a second window (keep it open while using the app)...
start "ShadeWalk Server" cmd /k call "%FL%" run -d web-server --web-port=8080

echo.
echo Waiting for the server to be ready (first run compiles, about 1-2 min)...
set /a tries=0
:waitloop
set /a tries+=1
powershell -NoProfile -Command "try { $null = Invoke-WebRequest -Uri 'http://localhost:8080' -UseBasicParsing -TimeoutSec 2; exit 0 } catch { exit 1 }"
if not errorlevel 1 goto ready
if %tries% GEQ 80 goto timedout
timeout /t 3 /nobreak >nul
goto waitloop

:ready
echo Server is up. Opening a phone-sized app window...
if exist "%CHROME%" (
  start "" "%CHROME%" --app=http://localhost:8080 --window-size=412,915
) else (
  start "" chrome --app=http://localhost:8080 --window-size=412,915
)
echo.
echo Opened. To STOP, close the "ShadeWalk Server" window.
goto end

:timedout
echo.
echo Timed out. Open the "ShadeWalk Server" window and check for errors,
echo then paste them back.

:end
pause
