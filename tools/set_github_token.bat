@echo off
title Shawn Kanban - 设置 GitHub Token
cd /d C://Users//Shen//.workbuddy//binaries//gh

echo ============================================================
echo   粘贴你的 GitHub Personal Access Token
echo.
echo   生成地址: https://github.com/settings/tokens/new
echo   勾选: repo  和  workflow
echo.
echo   粘贴后按回车
echo ============================================================
echo.

set "TOK="
set /p "TOK=Token: "

if not defined TOK (
  echo.
  echo Token 为空，未写入。
  pause
  exit /b 1
)

<nul set /p="%TOK%" > token.txt

echo.
echo 已写入 token.txt
for %%F in (token.txt) do echo   大小: %%~zF 字节
echo.
echo 回到对话里说一声，我来做剩下的部署。
echo.
pause
