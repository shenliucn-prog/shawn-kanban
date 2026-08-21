# -*- coding: utf-8 -*-
"""模拟 Kindle PW3 实际渲染（从用户照片反推的真实参数）。

关键发现（2026-08-22 由照片精确测量得出）：
- KOReader self.ui.dimen 在 PW3 上 = 物理像素 1072×1448（不是 758×1024）
- Font:getFace(size) 的 size 在 ffont 上 = 物理像素（行高 = size × 1.3）
- 字号 26 → 物理行高 ≈ 34px，照片实测 28-31px（接近，含边界）
复刻 KindleDash.koplugin/main.lua 布局，检查排版是否溢出/超宽。
"""
import json, urllib.request, math, sys

SCREEN_W, SCREEN_H = 1072, 1448  # PW3 物理像素（KOReader self.ui.dimen）
FONT = 26          # main.lua 字号（PW3 上 ≈ 物理像素）
PAD = 12           # 屏外边距
LINE_H = int(FONT * 1.3)  # TextBoxWidget 行高（line_height=0.3→1.3×字号）

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

def wc_for(sz, s):
    """按字号 sz 估算像素宽：CJK/全角=sz，ASCII/半角=sz/2（对应 main.lua textWidth）。"""
    w = 0
    half = sz / 2.0
    for ch in s:
        o = ord(ch)
        if o < 128:
            w += half
        else:
            w += sz
    return w

def price_text(v):
    if v is None:
        return "?"
    return num(v, 1 if v >= 1000 else 2)

def stock_cell(s):
    mkt = "美" if s.get("mkt") == "US" else ("A" if s.get("mkt") == "A" else " ")
    sign = "" if s.get("changePct") is None else ("+" if s.get("changePct") >= 0 else "-")
    p = "" if s.get("changePct") is None else ("%.1f%%" % abs(s.get("changePct")))
    return "%s %s %s %s%s" % (mkt, s.get("label", s.get("sym")), price_text(s.get("price")), sign, p)

def clock_cell(c):
    return "%s %s %s" % (c.get("city"), c.get("time"), c.get("date"))

def build_modules(d, colw):
    """复刻 main.lua buildModuleTexts，返回 [模块完整文本(含标题行), ...]。"""
    fullw = 2 * colw + 1
    def col2full(left, right=""):
        return pad_text(str(left), colw) + " " + pad_text(str(right), colw)
    def module_text(title, lines):
        return "\n".join([pad_text(title, fullw)] + lines)

    q = d.get("quotas", {})
    w = d.get("weather", {})
    st = d.get("stocks", {}).get("items", [])
    fx = d.get("fx", {})
    cl = d.get("clocks", {}).get("items", [])

    tok = []
    wb = q.get("workbuddy", {})
    if wb.get("ok"):
        t = wb.get("token", {})
        tok.append(pad_text("WorkBuddy %s/%s (%d%%)" % (t.get("remaining", "?"), t.get("size", "?"), t.get("percent") or 0), fullw))
    else:
        tok.append(pad_text("WorkBuddy 不可用", fullw))
    cc = q.get("claudecode", {})
    cx = q.get("codex", {})
    tok.append(col2full("ClaudeCode %s/%s" % (cc.get("used7d", "?"), cc.get("cap", "?")),
                        "Codex %s/%s" % (cx.get("used7d", "?"), cx.get("cap", "?"))))

    wea = []
    if w.get("ok"):
        wea.append(pad_text("天气 · %s  %s %s°C  高%s 低%s 湿%s%%" % (w.get("city", ""), w.get("text", ""), w.get("temp", "?"), w.get("high", "?"), w.get("low", "?"), w.get("humidity", "?")), fullw))
    else:
        wea.append(pad_text("天气 不可用", fullw))

    stk = []
    for i in range(0, len(st), 2):
        stk.append(col2full(stock_cell(st[i]), stock_cell(st[i + 1]) if i + 1 < len(st) else ""))

    fxx = [col2full("CNY " + num(fx.get("cny"), 3), "INR " + num(fx.get("inr"), 3))]

    clk = []
    for i in range(0, len(cl), 2):
        lc = cl[i]
        rc = cl[i + 1] if i + 1 < len(cl) else None
        clk.append(col2full(clock_cell(lc), clock_cell(rc) if rc else ""))

    upd = [pad_text("更新 00:05:00", fullw)]

    return [
        module_text("TOKEN USAGE", tok),
        module_text("天气", wea),
        module_text("股市", stk),
        module_text("汇率", fxx),
        module_text("时钟", clk),
        module_text("更新", upd),
    ]

def choose_size(d, availW, availH):
    """复刻 main.lua chooseSize：从 26 往下选，直到 行宽≤availW 且 总高≤availH。"""
    for sz in (26, 24, 22, 20, 18):
        half = max(1, sz // 2)
        colw = int((availW - half) / 2 / half)
        mods = build_modules(d, colw)
        ok, total_lines = True, 0
        for m in mods:
            for line in m.split("\n"):
                total_lines += 1
                if wc_for(sz, line) > availW:
                    ok = False
                    break
            if not ok:
                break
        if ok:
            lineH = math.ceil(sz * 1.3)
            titleH = math.ceil((sz + 2) * 1.3)
            totalH = titleH + total_lines * lineH + len(mods) * 10
            if totalH <= availH:
                return sz
    return 18

def render(d):
    """返回 (lines, sz, colw)。lines 为所有模块的所有行。"""
    availW = SCREEN_W - 2 * PAD
    availH = SCREEN_H - 2 * PAD
    sz = choose_size(d, availW, availH)
    half = max(1, sz // 2)
    colw = int((availW - half) / 2 / half)
    lines = []
    for m in build_modules(d, colw):
        lines.extend(m.split("\n"))
    return lines, sz, colw

def main():
    if len(sys.argv) > 1:
        d = json.load(open(sys.argv[1], encoding="utf-8"))
    else:
        d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    lines, sz, colw = render(d)
    avail_w = SCREEN_W - 2 * PAD
    avail_h = SCREEN_H - 2 * PAD
    line_h = math.ceil(sz * 1.3)
    total_h = 0
    print("=== 排版检查 (屏幕 %dx%d, 字号 %d(自适应), 列宽 %d单位, 可用 %dx%d) ===" % (SCREEN_W, SCREEN_H, sz, colw, avail_w, avail_h))
    warn = 0
    for line in lines:
        w = wc_for(sz, line)
        wraps = max(0, math.ceil(w / avail_w) - 1)
        used = (wraps + 1) * line_h
        total_h += used
        status = "OK"
        if w > avail_w:
            warn += 1
            status = "!! 超宽 %dpx" % (w - avail_w)
        print("  %-46s %6.0f  %s" % (line[:46] if len(line) <= 46 else line[:43] + "...", w, status))
    print("---")
    print("总行数: %d, 总高: %dpx, 可用高: %dpx, %s" % (
        len(lines), total_h, avail_h,
        "余量 %dpx" % (avail_h - total_h) if total_h <= avail_h else "!! 溢出 %dpx" % (total_h - avail_h)))
    print("超宽行数: %d" % warn)

if __name__ == "__main__":
    main()
