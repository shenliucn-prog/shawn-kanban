' 后台静默启动额度上报器（放到 shell:startup 即可开机自启）
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & "C:\Users\Shen\WorkBuddy\2026-08-16-01-28-56\tools\report_quota.bat" & chr(34), 0, false
