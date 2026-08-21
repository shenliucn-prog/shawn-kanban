# -*- coding: utf-8 -*-
"""把 Shawn Kanban 看板渲染成 Kindle PW3 (758x1024) 的 e-ink 模拟图。"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kindle_preview import render, SCREEN_W, SCREEN_H, FONT, PAD, LINE_H
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
    lines = render(d)
    img = Image.new("RGB", (SCREEN_W, SCREEN_H), "white")
    draw = ImageDraw.Draw(img)
    font = load_font(FONT)
    y = PAD
    for line in lines:
        draw.text((PAD, y), line, fill="black", font=font)
        y += LINE_H
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kindle_preview.png")
    img.save(out)
    print("已生成:", out, "(%dx%d)" % (SCREEN_W, SCREEN_H))

def json_load():
    import json, urllib.request
    return json.load(urllib.request.urlopen("http://127.0.0.1:8787/api/dashboard", timeout=20))

if __name__ == "__main__":
    main()
