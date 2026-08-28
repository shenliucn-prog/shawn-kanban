@echo off
rem 本机 AI 额度上报器（常驻循环）
rem 前置：复制 report_secrets.example.bat 为 report_secrets.bat 并填入 Token/仓库
setlocal
cd /d C:\Users\Shen\WorkBuddy\2026-08-16-01-28-56

if exist tools\report_secrets.bat call tools\report_secrets.bat

rem 必须用托管 Node 22.x：better-sqlite3 预编译为 ABI 127，系统 node v24 是 ABI 137 会加载失败
set "NODE=C:\Users\Shen\.workbuddy\binaries\node\versions\22.12.0\node.exe"

if "%GITHUB_TOKEN%"=="" (
  echo [warn] GITHUB_TOKEN 未设置，只写本地 data\quotas.json，不推远端
)
if "%GITHUB_REPO%"=="" (
  echo [warn] GITHUB_REPO 未设置，只写本地 data\quotas.json，不推远端
)

:loop
"%NODE%" tools\report_quota.js --loop >> tools\report_quota.log 2>&1
echo [%date% %time%] reporter exited (code %errorlevel%), restarting in 30s... >> tools\report_quota.log
timeout /t 30 /nobreak > nul
goto loop
