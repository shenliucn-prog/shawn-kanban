# -*- coding: utf-8 -*-
"""排版 5 遍检查：真实数据 + 最坏情况（最长名称/大价格/大涨跌），确保一屏不翻页。
复刻 main.lua chooseSize 的精确逻辑（scale=1.7867, lineH=1.3, 模块开销22, 缓冲40）。
判定：0 超宽 且 总高 <= 可用高。
"""
import sys, os, math, json, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kindle_preview as K

def worst_case(d):
    """构造最坏情况：名称拉最长、价格/涨跌取大值。"""
    import copy
    d = copy.deepcopy(d)
    for i, s in enumerate(d.get("stocks", {}).get("items", [])):
        s["name"] = s["label"] = ("深证成指" if i % 2 else "贵州茅台")  # 4 字全角最宽
        s["price"] = 999999.99  # 显示 1000000.0（9 字符），逼迫字号自适应降档
        s["changePct"] = 100.0
    return d

def check(d, label):
    avail_w = K.SCREEN_W - 2 * K.PAD
    avail_h = K.SCREEN_H - 2 * K.PAD
    sz, colw, tbw = K.choose_size(d, avail_w, avail_h)
    mods = K.build_modules(d, colw)
    phys_sz = math.ceil(sz * K.SCALE)
    title_phys_sz = math.ceil((sz + 2) * K.SCALE)
    main_title_phys_sz = math.ceil((sz + 4) * K.SCALE)

    # 宽度检查
    overflow = 0
    for m in mods:
        if K.wc_for(title_phys_sz, m["title"]) > tbw:
            overflow += 1
        for line in m["lines"]:
            if K.wc_for(phys_sz, line) > tbw:
                overflow += 1
                print(f"    !! 超宽: {line[:44]}")

    # 高度（与 choose_size 同口径）
    lineH = math.ceil(phys_sz * 1.3)
    titleH = math.ceil(title_phys_sz * 1.3)
    mainTitleH = math.ceil(main_title_phys_sz * 1.3)
    total_h = mainTitleH
    for m in mods:
        total_h += titleH + max(len(m["lines"]), K.MIN_LINES_PER_MODULE) * lineH
    total_h += len(mods) * 22 + 40

    margin = avail_h - total_h
    ok = (overflow == 0 and margin >= 0)
    print(f"  [{label}] 字号={sz}(物理{phys_sz}) colw={colw} 总高={total_h}px 可用={avail_h}px 余量={margin}px 超宽={overflow} -> {'✓ 一屏' if ok else '✗ 需修正'}")
    return ok

def main():
    d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    all_ok = True
    print(f"=== 排版 5 遍检查（屏幕 {K.SCREEN_W}x{K.SCREEN_H}, scale={K.SCALE:.4f}, 字号自适应 26→16）===")
    for i in range(1, 6):
        if i % 2 == 1:
            all_ok &= check(worst_case(d), f"第{i}遍·最坏情况")
        else:
            all_ok &= check(d, f"第{i}遍·真实数据")
    print("=== 结论:", "全部通过，一屏显示" if all_ok else "有超标，需压缩 ===")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
