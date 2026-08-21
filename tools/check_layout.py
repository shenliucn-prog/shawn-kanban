# -*- coding: utf-8 -*-
"""排版 5 遍检查：真实数据 + 最坏情况（最长名称/大价格/大涨跌），确保一屏不翻页。
判定：0 超宽 且 总高 ≤ 可用高 - 80px 余量。
"""
import sys, os, math, json, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kindle_preview as K

def worst_case(d):
    """构造最坏情况：名称拉最长、价格/涨跌取大值，走势图满 8 字符。"""
    import copy
    d = copy.deepcopy(d)
    for i, s in enumerate(d.get("stocks", {}).get("items", [])):
        s["name"] = s["label"] = ("深证成指" if i % 2 else "贵州茅台")  # 4 字全角最宽
        s["price"] = 9999.99  # 显示 10000.0（7 字符，现实量级上界）
        s["changePct"] = 10.0
        if s.get("spark"):
            s["spark"]["closes"] = [100 + (j % 8) for j in range(30)]
    return d

def check(d, label):
    lines = K.render(d)
    avail_w = K.SCREEN_W - 2 * K.PAD
    avail_h = K.SCREEN_H - 2 * K.PAD
    total_h = 0
    overflow = 0
    for line in lines:
        w = K.wc(line)
        wraps = max(0, math.ceil(w / avail_w) - 1)
        total_h += (wraps + 1) * K.LINE_H
        if w > avail_w:
            overflow += 1
            print(f"    !! 超宽 {w}px: {line[:40]}")
    margin = avail_h - total_h
    ok = (overflow == 0 and margin >= 80)
    print(f"  [{label}] 行数={len(lines)} 总高={total_h}px 可用={avail_h}px 余量={margin}px 超宽={overflow}  -> {'✓ 一屏' if ok else '✗ 需修正'}")
    return ok

def main():
    d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    all_ok = True
    print("=== 排版 5 遍检查（字号 %d, 屏幕 %dx%d）===" % (K.FONT, K.SCREEN_W, K.SCREEN_H))
    for i in range(1, 6):
        if i % 2 == 1:
            all_ok &= check(worst_case(d), f"第{i}遍·最坏情况")
        else:
            all_ok &= check(d, f"第{i}遍·真实数据")
    print("=== 结论:", "全部通过，一屏显示" if all_ok else "有超标，需压缩 ===")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
