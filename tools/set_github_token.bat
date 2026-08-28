@echo off
chcp 65001 >nul
title Shawn Kanban - 设置 GitHub Token
cd /d C:\Users\Shen\.workbuddy\binaries\gh

echo ============================================================
echo   粘贴你的 GitHub Personal Access Token
echo.
echo   生成地址: https://github.com/settings/tokens/new
echo   需要勾选: repo  和  workflow
echo.
echo   粘贴后按回车（屏幕上看不到输入，这是正常的）
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s = Read-Host 'Token' -AsSecureString;" ^
  "$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);" ^
  "$p = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b).Trim();" ^
  "[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b);" ^
  "if ($p -eq '') { Write-Host ''; Write-Host 'Token 为空，未写入。' -ForegroundColor Red; exit 1 };" ^
  "Set-Content -LiteralPath 'C:\Users\Shen\.workbuddy\binaries\gh\token.txt' -Value $p -NoNewline -Encoding ascii;" ^
  "Write-Host '';" ^
  "Write-Host ('已写入 ' + $p.Length + ' 个字符到 token.txt') -ForegroundColor Green;" ^
  "Write-Host ('前缀: ' + $p.Substring(0, [Math]::Min(7, $p.Length)) + '...') -ForegroundColor Gray"

echo.
echo 完成后回到对话里说一声，我来做剩下的部署。
echo.
pause
