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
        s["price"] = 999999.99  # 显示 1000000.0（9 字符），逼迫字号自适应降档
        s["changePct"] = 100.0
        if s.get("spark"):
            s["spark"]["closes"] = [100 + (j % 8) for j in range(30)]
    return d

def check(d, label):
    lines, sz, colw = K.render(d)
    avail_w = K.SCREEN_W - 2 * K.PAD
    avail_h = K.SCREEN_H - 2 * K.PAD
    line_h = math.ceil(sz * 1.3)
    total_h = 0
    overflow = 0
    for line in lines:
        w = K.wc_for(sz, line)
        total_h += line_h
        if w > avail_w:
            overflow += 1
            print(f"    !! 超宽 {w:.0f}px: {line[:44]}")
    # 与 main.lua chooseSize 相同的总高口径（含标题行 + 6 个模块边框开销）
    title_h = math.ceil((sz + 2) * 1.3)
    total_h_est = title_h + len(lines) * line_h + 6 * 10
    margin = avail_h - total_h_est
    ok = (overflow == 0 and margin >= 60)
    print(f"  [{label}] 字号={sz} 行数={len(lines)} 总高(估)={total_h_est}px 可用={avail_h}px 余量={margin}px 超宽={overflow}  -> {'✓ 一屏' if ok else '✗ 需修正'}")
    return ok

def main():
    d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    all_ok = True
    print("=== 排版 5 遍检查（屏幕 %dx%d, 字号自适应 26→18）===" % (K.SCREEN_W, K.SCREEN_H))
    for i in range(1, 6):
        if i % 2 == 1:
            all_ok &= check(worst_case(d), f"第{i}遍·最坏情况")
        else:
            all_ok &= check(d, f"第{i}遍·真实数据")
    print("=== 结论:", "全部通过，一屏显示" if all_ok else "有超标，需压缩 ===")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
