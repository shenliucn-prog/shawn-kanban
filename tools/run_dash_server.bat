@echo off
cd /d C:\Users\Shen\WorkBuddy\2026-08-16-01-28-56
rem 必须用托管 Node 22.x：better-sqlite3 预编译为 ABI 127，系统 node v24 是 ABI 137 会加载失败（workbuddy 报 db unavailable）
set "NODE=C:\Users\Shen\.workbuddy\binaries\node\versions\22.12.0\node.exe"
:loop
"%NODE%" src/index.js >> C:\Users\Shen\WorkBuddy\2026-08-16-01-28-56\tools\dash_server.log 2>&1
echo [%date% %time%] server exited (code %errorlevel%), restarting in 3s... >> C:\Users\Shen\WorkBuddy\2026-08-16-01-28-56\tools\dash_server.log
timeout /t 3 /nobreak > nul
goto loop
