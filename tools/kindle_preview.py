# -*- coding: utf-8 -*-
"""模拟 Kindle PW3 (KOReader kindlepw2, 逻辑分辨率 758x1024) 渲染 Shawn Kanban 看板。
复刻 KindleDash.koplugin/main.lua 的 renderText 逻辑，检查排版是否溢出/超宽。
"""
import json, urllib.request, math, sys

SCREEN_W, SCREEN_H = 758, 1024
FONT = 24          # main.lua showDashboard 用的字号
PAD = 16           # frame padding
LINE_H = int(FONT * 1.18)  # TextBoxWidget 默认行高近似
CH_FULL, CH_HALF = FONT, FONT // 2   # 全角/半角近似像素宽

SPARK = ["▁","▂","▃","▄","▅","▆","▇","█"]

def wc(s):
    """按 KOReader 比例字体近似计算像素宽：CJK/全角=CH_FULL，ASCII/半角=CH_HALF。"""
    w = 0
    for ch in s:
        o = ord(ch)
        if o < 128:
            w += CH_HALF
        elif 0xFF00 <= o <= 0xFFEF or o in (0x2026, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D):
            w += CH_FULL
        elif 0x2581 <= o <= 0x2588:
            w += CH_FULL  # 块字符按全宽保守计算
        else:
            w += CH_FULL
    return w

def pad_text(s, width):
    s = str(s)
    return s + " " * max(0, width - len_units(s))

def len_units(s):
    n = 0
    for ch in s:
        o = ord(ch)
        if o < 128:
            n += 1
        else:
            n += 2
    return n

def sparkline(closes, n=8):
    if not closes or len(closes) < 2:
        return ""
    pts = []
    step = len(closes) / n
    for i in range(1, n + 1):
        idx = min(int(math.floor((i - 1) * step)) , len(closes) - 1)
        pts.append(closes[idx])
    lo, hi = min(pts), max(pts)
    span = hi - lo
    if span <= 0:
        return ""
    out = []
    for v in pts:
        lv = int((v - lo) / span * 8) + 1
        lv = max(1, min(8, lv))
        out.append(SPARK[lv - 1])
    return "".join(out)

def num(v, d=None):
    if v is None:
        return "n/a"
    if d is not None:
        return ("%%.%df" % d) % v
    return str(v)

def render(d):
    L = []
    q = d.get("quotas", {})
    L.append("SHAWN KANBAN")
    wb = q.get("workbuddy", {})
    if wb.get("ok"):
        t = wb.get("token", {})
        L.append("WorkBuddy %s  剩余%s/%s (%d%%)" % (wb.get("model", "?"), t.get("remaining", "?"), t.get("size", "?"), t.get("percent") or 0))
    else:
        L.append("WorkBuddy  不可用 (%s)" % wb.get("error", ""))
    cc = q.get("claudecode", {})
    L.append("ClaudeCode 本周 %s / %s%s" % (cc.get("used7d", "?"), cc.get("cap", "?"), "" if cc.get("ok") else "  (本地)"))
    cx = q.get("codex", {})
    L.append("Codex      本周 %s / %s%s" % (cx.get("used7d", "?"), cx.get("cap", "?"), "" if cx.get("ok") else "  (本地)"))
    L.append("")
    w = d.get("weather", {})
    L.append("── 天气 · %s ──" % w.get("city", ""))
    if w.get("ok"):
        L.append("%s %s°C  高%s  低%s  湿%s%%" % (w.get("text", ""), w.get("temp", "?"), w.get("high", "?"), w.get("low", "?"), w.get("humidity", "?")))
    else:
        L.append("  不可用 (%s)" % w.get("error", ""))
    L.append("")
    L.append("── 股市 ──")
    for s in d.get("stocks", {}).get("items", []):
        mkt = "美" if s.get("mkt") == "US" else ("A" if s.get("mkt") == "A" else " ")
        arrow = "" if s.get("changePct") is None else ("↑" if s.get("changePct") >= 0 else "↓")
        pct = "" if s.get("changePct") is None else ("%+.1f%%" % s.get("changePct"))
        mini = ""
        sp = s.get("spark")
        if sp and sp.get("closes") and len(sp["closes"]) >= 2:
            mini = " " + sparkline(sp["closes"], 8)
        L.append("[%s] %s %s %s%s%s" % (mkt, s.get("label", s.get("sym")), s.get("price", "?"), arrow, pct, mini))
    fx = d.get("fx", {})
    L.append("── 汇率 (1 %s) ──" % fx.get("base", "USD"))
    L.append("CNY %s    INR %s" % (num(fx.get("cny"), 3), num(fx.get("inr"), 3)))
    L.append("")
    L.append("── 世界时钟 ──")
    for c in d.get("clocks", {}).get("items", []):
        L.append("%s %s %s" % (pad_text(c.get("city", ""), 8), c.get("time"), c.get("date")))
    L.append("更新 23:34:00")
    return L

def main():
    if len(sys.argv) > 1:
        d = json.load(open(sys.argv[1], encoding="utf-8"))
    else:
        d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    lines = render(d)
    avail_w = SCREEN_W - 2 * PAD
    avail_h = SCREEN_H - 2 * PAD
    total_h = 0
    print("=== 排版检查 (屏幕 %dx%d, 字号 %d, 可用 %dx%d) ===" % (SCREEN_W, SCREEN_H, FONT, avail_w, avail_h))
    print("%-52s %7s %s" % ("行内容", "宽(px)", "状态"))
    warn = 0
    for i, line in enumerate(lines):
        w = wc(line)
        wraps = max(0, math.ceil(w / avail_w) - 1)
        used = (wraps + 1) * LINE_H
        total_h += used
        status = "OK"
        if w > avail_w:
            warn += 1
            status = "!! 超宽 %dpx(约换%d行)" % (w - avail_w, wraps)
        print("  %-50s %6d  %s" % (line[:50] if len(line) <= 50 else line[:47] + "...", w, status))
    print("---")
    print("总行数(逻辑): %d, 总高(含换行): %dpx, 可用高: %dpx, %s" % (
        len(lines), total_h, avail_h,
        "余量 %dpx" % (avail_h - total_h) if total_h <= avail_h else "!! 溢出 %dpx(需滚动)" % (total_h - avail_h)))
    print("超宽行数: %d" % warn)

if __name__ == "__main__":
    main()
