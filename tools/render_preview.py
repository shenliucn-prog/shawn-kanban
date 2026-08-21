# -*- coding: utf-8 -*-
"""渲染 Kindle PW3 (1072x1448) 模拟图，复刻 main.lua showDashboard 布局。
- 模块标题粗体（tfont=NotoSans-Bold 模拟用 msyhbd.ttc）
- 两列严格中线对齐：左列右对齐 + 右列左对齐
- 撑满屏：根据余量动态增加模块 padding/margin
"""
import sys, os, json, urllib.request, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kindle_preview import build_modules, choose_size, SCREEN_W, SCREEN_H, PAD, SCALE
from PIL import Image, ImageDraw, ImageFont

FONT_REGULAR = r"C:/Windows/Fonts/msyh.ttc"      # 微软雅黑 Regular
FONT_BOLD    = r"C:/Windows/Fonts/msyhbd.ttc"    # 微软雅黑 Bold

def load_font(path, size):
    if os.path.exists(path):
        try: return ImageFont.truetype(path, size)
        except Exception: pass
    return ImageFont.load_default()

def text_w(draw, text, font):
    """返回文本像素宽（draw.textsize 兼容 Pillow 9-）。"""
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        return bbox[2] - bbox[0]
    except Exception:
        try: return draw.textsize(text, font=font)[0]
        except Exception: return len(text) * 10

def main():
    d = json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))
    availW = SCREEN_W - 2 * PAD
    availH = SCREEN_H - 2 * PAD
    sz, colwW, gap = choose_size(d, availW, availH)
    mods = build_modules(d)

    # 撑满屏逻辑（复刻 main.lua）
    physSz = math.ceil(sz * SCALE)
    titlePhysSz = math.ceil((sz + 2) * SCALE)
    mainTitlePhysSz = math.ceil((sz + 4) * SCALE)
    lineH = math.ceil(physSz * 1.3)
    titleH = math.ceil(titlePhysSz * 1.3)
    mainTitleH = math.ceil(mainTitlePhysSz * 1.3)
    totalLines = sum(1 + len(m["lines"]) for m in mods)
    baseOverhead = 16
    totalH = mainTitleH + totalLines * lineH + len(mods) * baseOverhead
    extra = max(0, availH - totalH)
    extraPerMod = extra // len(mods)
    modMargin = 2 + extraPerMod // 2
    modPadding = 4 + extraPerMod // 4

    img = Image.new("RGB", (SCREEN_W, SCREEN_H), "white")
    draw = ImageDraw.Draw(img)
    font_body = load_font(FONT_REGULAR, physSz)
    font_title = load_font(FONT_BOLD, titlePhysSz)
    font_main = load_font(FONT_BOLD, mainTitlePhysSz)

    tbw = availW - 4
    y = PAD
    # 主标题（粗体）
    draw.text((PAD, y), "Shawn Kanban", fill="black", font=font_main)
    y += mainTitleH + 4

    for m in mods:
        # 模块框（含 padding+margin）
        mod_lines_h = (1 + len(m["lines"])) * lineH  # 标题 + 内容行
        frame_h = mod_lines_h + 2 * (modPadding + 1)  # border1*2
        x0 = PAD
        y0 = y
        x1 = SCREEN_W - PAD
        y1 = y + frame_h
        # margin 上下各 modMargin
        y += modMargin
        # 画框
        draw.rectangle([PAD, y, SCREEN_W - PAD, y + frame_h], outline="black", width=1)
        ty = y + modPadding + 1
        # 标题（粗体，左对齐）
        draw.text((PAD + modPadding + 1, ty), m["title"], fill="black", font=font_title)
        ty += lineH
        # 内容行
        for line in m["lines"]:
            if line["kind"] == "single":
                draw.text((PAD + modPadding + 1, ty), line["text"], fill="black", font=font_body)
            else:
                # 左列右对齐到中线，右列左对齐从中线开始
                midx = PAD + modPadding + 1 + colwW + gap // 2
                # 左列：从 (midx - gap//2 - textW(left)) 开始
                lw = text_w(draw, line["left"], font_body)
                draw.text((midx - gap // 2 - lw, ty), line["left"], fill="black", font=font_body)
                # 右列：从 midx + gap//2 开始
                draw.text((midx + gap // 2, ty), line["right"], fill="black", font=font_body)
                # 中线参考线（淡灰，调试用）
                # draw.line([(midx, ty), (midx, ty + lineH)], fill="gray", width=1)
            ty += lineH
        y = y1 + modMargin

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kindle_preview.png")
    img.save(out)
    print(f"已生成: {out} ({SCREEN_W}x{SCREEN_H}, 字号 {sz}/物理{physSz}, 列宽 {colwW}px, 框padding {modPadding}/margin {modMargin})")

if __name__ == "__main__":
    main()
