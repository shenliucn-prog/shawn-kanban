# -*- coding: utf-8 -*-
"""后台捕获"凭据访问"弹窗来源窗口。每 2 秒枚举可见窗口，记录新出现的窗口。
日志写到 tools/cred_popup_capture.log。用法: python3 tools/capture_cred_popup.py
"""
import ctypes, ctypes.wintypes, time, os, subprocess, sys

user32 = ctypes.windll.user32
known = set()

def enum_windows():
    out = []
    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.wintypes.HWND, ctypes.wintypes.LPARAM)
    def cb(hwnd, lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length <= 0:
            return True
        buf = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buf, length + 1)
        pid = ctypes.wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        out.append((pid.value, buf.value))
        return True
    user32.EnumWindows(cb, 0)
    return out

def pid_name_map():
    m = {}
    try:
        r = subprocess.run(
            ['wmic', 'process', 'get', 'ProcessId,Name'],
            capture_output=True, timeout=10
        ).stdout.decode('gbk', 'replace')
        for line in r.splitlines():
            parts = line.strip().rsplit(None, 1)
            if len(parts) == 2 and parts[1].isdigit():
                m[int(parts[1])] = parts[0]
    except Exception:
        pass
    return m

def main():
    log = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cred_popup_capture.log')
    with open(log, 'a', encoding='utf-8') as f:
        f.write(f"\n=== 监视开始 {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        f.flush()
        last_pids = {}
        while True:
            try:
                wins = enum_windows()
                names = pid_name_map()
                seen_this_round = set()
                for pid, title in wins:
                    key = (pid, title)
                    seen_this_round.add(key)
                    if key not in known:
                        known.add(key)
                        name = names.get(pid, '?')
                        f.write(f"{time.strftime('%H:%M:%S')} 新窗口 PID={pid} [{name}] 「{title}」\n")
                        f.flush()
            except Exception as e:
                with open(log, 'a', encoding='utf-8') as f:
                    f.write(f"{time.strftime('%H:%M:%S')} 错误: {e}\n")
            time.sleep(2)

if __name__ == '__main__':
    main()
