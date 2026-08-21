# -*- coding: utf-8 -*-
"""模拟 Kindle PW3 实际渲染（从用户照片反推的真实参数）。

关键发现（2026-08-22 由照片精确测量得出）：
- KOReader self.ui.dimen 在 PW3 上 = 物理像素 1072×1448
- Font:getFace(size) 内部 Screen:scaleBySize(size)，系数 ≈1.416
- 实际物理字号 = 逻辑字号 × 1.416；行高 = 物理字号 × 1.3
复刻 KindleDash.koplugin/main.lua 布局，检查排版是否溢出/超宽。
"""
import json, urllib.request, math, sys

SCREEN_W, SCREEN_H = 1072, 1448  # PW3 物理像素
PAD = 8                            # 屏外边距（与 main.lua showDashboard pad 一致）
SCALE = 1.416                      # Screen:scaleBySize 系数
SIZES = (30, 28, 26, 24, 22, 20, 18, 16)

def num(v, d=None):
    if v is None: return "n/a"
    if d is not None: return ("%%.%df" % d) % v
    return str(v)

def wc_for(phys_sz, s):
    """按物理字号 phys_sz 估算像素宽：CJK=phys_sz，ASCII=phys_sz/2（对应 main.lua textWidth）。"""
    w = 0
    half = phys_sz / 2.0
    for ch in s:
        w += half if ord(ch) < 128 else phys_sz
    return w

def price_text(v):
    if v is None: return "?"
    return num(v, 1 if v >= 1000 else 2)

def stock_cell(s):
    mkt = "美" if s.get("mkt") == "US" else ("A" if s.get("mkt") == "A" else " ")
    sign = "" if s.get("changePct") is None else ("+" if s.get("changePct") >= 0 else "-")
    p = "" if s.get("changePct") is None else ("%.1f%%" % abs(s.get("changePct")))
    return "%s %s %s %s%s" % (mkt, s.get("label", s.get("sym")), price_text(s.get("price")), sign, p)

def clock_cell(c):
    return "%s %s %s" % (c.get("city"), c.get("time"), c.get("date"))

def single(text): return {"kind": "single", "text": text}
def double(left, right=""): return {"kind": "double", "left": left, "right": right}

def build_modules(d):
    """复刻 main.lua buildModules，返回结构化模块数据 [{title, lines}, ...]。"""
    q = d.get("quotas", {})
    w = d.get("weather", {})
    st = d.get("stocks", {}).get("items", [])
    fx = d.get("fx", {})
    cl = d.get("clocks", {}).get("items", [])

    tok = []
    wb = q.get("workbuddy", {})
    if wb.get("ok"):
        t = wb.get("token", {})
        tok.append(single("WorkBuddy %s/%s (%d%%)" % (t.get("remaining", "?"), t.get("size", "?"), t.get("percent") or 0)))
    else:
        tok.append(single("WorkBuddy 不可用"))
    cc = q.get("claudecode", {})
    cx = q.get("codex", {})
    tok.append(double("ClaudeCode %s/%s" % (cc.get("used7d", "?"), cc.get("cap", "?")),
                      "Codex %s/%s" % (cx.get("used7d", "?"), cx.get("cap", "?"))))

    wea = []
    if w.get("ok"):
        wea.append(single("%s  %s %s°C  高%s 低%s 湿%s%%" % (
            w.get("city", ""), w.get("text", ""), w.get("temp", "?"),
            w.get("high", "?"), w.get("low", "?"), w.get("humidity", "?"))))
    else:
        wea.append(single("天气 不可用"))

    stk = []
    for i in range(0, len(st), 2):
        stk.append(double(stock_cell(st[i]), stock_cell(st[i + 1]) if i + 1 < len(st) else ""))

    fxx = [double("CNY " + num(fx.get("cny"), 3), "INR " + num(fx.get("inr"), 3))]

    clk = []
    for i in range(0, len(cl), 2):
        clk.append(double(clock_cell(cl[i]), clock_cell(cl[i + 1]) if i + 1 < len(cl) else ""))

    upd = [single("更新 00:05:00  顶部下滑返回")]

    return [
        {"title": "Token Usage", "lines": tok},
        {"title": "天气",        "lines": wea},
        {"title": "股市",        "lines": stk},
        {"title": "汇率",        "lines": fxx},
        {"title": "时钟",        "lines": clk},
        {"title": "更新",        "lines": upd},
    ]

def choose_size(d, availW, availH):
    """复刻 main.lua chooseSize：从大到小试，对 single 检查 tbw，对 double 检查 colwW（严格中线对齐）。"""
    gap = 4
    tbw = availW - 4
    colwW = (availW - gap) // 2
    for sz in SIZES:
        phys_sz = math.ceil(sz * SCALE)
        title_phys_sz = math.ceil((sz + 2) * SCALE)
        mods = build_modules(d)
        ok, total_lines = True, 0
        for m in mods:
            total_lines += 1
            if wc_for(title_phys_sz, m["title"]) > tbw:
                ok = False; break
            for line in m["lines"]:
                total_lines += 1
                if line["kind"] == "single":
                    if wc_for(phys_sz, line["text"]) > tbw:
                        ok = False; break
                else:
                    if wc_for(phys_sz, line["left"]) > colwW or wc_for(phys_sz, line["right"]) > colwW:
                        ok = False; break
            if not ok: break
        if ok:
            lineH = math.ceil(phys_sz * 1.3)
            titleH = math.ceil(title_phys_sz * 1.3)
            totalH = titleH + total_lines * lineH + len(mods) * 16
            if totalH <= availH:
                return sz, colwW, gap
    return SIZES[-1], colwW, gap

def main():
    if len(sys.argv) > 1:
        d = json.load(open(sys.argv[1], encoding="utf-8"))
    else:
        d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    availW = SCREEN_W - 2 * PAD
    availH = SCREEN_H - 2 * PAD
    sz, colwW, gap = choose_size(d, availW, availH)
    tbw = availW - 4
    phys_sz = math.ceil(sz * SCALE)
    title_phys_sz = math.ceil((sz + 2) * SCALE)
    lineH = math.ceil(phys_sz * 1.3)
    titleH = math.ceil(title_phys_sz * 1.3)
    mods = build_modules(d)
    total_h = titleH + sum(1 + len(m["lines"]) for m in mods) * lineH + len(mods) * 16
    print("=== 排版检查 (屏 %dx%d, 字号 %d(自适应→物理%d), 列宽 %dpx, 可用 %dx%d) ===" % (
        SCREEN_W, SCREEN_H, sz, phys_sz, colwW, availW, availH))
    warn = 0
    for m in mods:
        print("┌─ %s ─┐ (标题粗体)" % m["title"])
        w = wc_for(title_phys_sz, m["title"])
        if w > tbw:
            warn += 1
            print("  !! 标题超宽 %dpx" % (w - tbw))
        for line in m["lines"]:
            if line["kind"] == "single":
                w = wc_for(phys_sz, line["text"])
                status = "OK" if w <= tbw else "!! 超宽 %dpx" % (w - tbw)
                if w > tbw: warn += 1
                print("  %-50s %6.0f  %s" % (line["text"][:50], w, status))
            else:
                lw = wc_for(phys_sz, line["left"])
                rw = wc_for(phys_sz, line["right"])
                lstatus = "OK" if lw <= colwW else "!! 左超 %dpx" % (lw - colwW)
                rstatus = "OK" if rw <= colwW else "!! 右超 %dpx" % (rw - colwW)
                if lw > colwW: warn += 1
                if rw > colwW: warn += 1
                print("  L %-26s %5.0f  %s" % (line["left"][:26], lw, lstatus))
                print("  R %-26s %5.0f  %s" % (line["right"][:26], rw, rstatus))
    print("---")
    print("模块数: %d, 总高: %dpx, 可用高: %dpx, %s" % (
        len(mods), total_h, availH,
        "余量 %dpx" % (availH - total_h) if total_h <= availH else "!! 溢出 %dpx" % (total_h - availH)))
    print("超宽/超列行数: %d" % warn)

if __name__ == "__main__":
    main()
