# -*- coding: utf-8 -*-
"""把 Shawn Kanban 看板渲染成 Kindle PW3 (758x1024) 的 e-ink 模拟图。"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kindle_preview import render, build_modules, SCREEN_W, SCREEN_H, PAD
from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = [
    r"C:/Windows/Fonts/msyh.ttc",   # 微软雅黑
    r"C:/Windows/Fonts/msyhbd.ttc",
    r"C:/Windows/Fonts/simhei.ttf", # 黑体
    r"C:/Windows/Fonts/simsun.ttc", # 宋体
]

def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()

def main():
    d = json_load()
    lines, sz, colw = render(d)
    img = Image.new("RGB", (SCREEN_W, SCREEN_H), "white")
    draw = ImageDraw.Draw(img)
    font = load_font(sz)
    title_font = load_font(sz + 2)
    line_h = int(sz * 1.3)
    title_h = int((sz + 2) * 1.3)
    pad_in = 8  # 框内 padding（模拟 FrameContainer padding=6 + border）
    border = 1
    margin = 4

    y = PAD
    draw.text((PAD, y), "SHAWN KANBAN", fill="black", font=title_font)
    y += title_h + 4

    for m in build_modules(d, colw):
        mod_lines = m.split("\n")
        h = len(mod_lines) * line_h + 2 * (pad_in + border)
        draw.rectangle([PAD, y, SCREEN_W - PAD, y + h], outline="black", width=border)
        ty = y + pad_in + border
        for line in mod_lines:
            draw.text((PAD + pad_in + border, ty), line, fill="black", font=font)
            ty += line_h
        y += h + margin

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kindle_preview.png")
    img.save(out)
    print("已生成:", out, "(%dx%d, 字号%d)" % (SCREEN_W, SCREEN_H, sz))

def json_load():
    import json, urllib.request
    return json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))

if __name__ == "__main__":
    main()
