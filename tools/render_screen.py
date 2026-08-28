# -*- coding: utf-8 -*-
"""Shawn Kanban 整屏渲染器（PC 端出图，Kindle 端只显示）。

把 /api/dashboard JSON 渲染成 1072x1448 印刷布告栏风整屏图，
16 级灰度（GRAY=128 / LIGHT_GRAY=200）最终 Floyd-Steinberg 抖动转 1-bit PNG。
静态数据（句子库）从 data/ 读；新闻/节日/时钟/额度均由服务端提供。
"""
import sys, os, json, math, re, urllib.request, argparse
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont

# ---------- 屏幕与设计常量 ----------
SCREEN_W, SCREEN_H = 1072, 1448
PAD = 40
CONTENT_W = SCREEN_W - 2 * PAD
BLACK, GRAY, LIGHT_GRAY, WHITE = 0, 128, 200, 255

# 字体：本机用微软雅黑，Linux/CI 用开源 Noto Sans CJK。
# 优先级：环境变量 > 候选路径 > 默认值。找不到时 f() 会退回 load_default（不显示中文）。
LINUX_REG = [
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf',
    './fonts/NotoSansSC-Regular.otf',
    './fonts/NotoSansCJKsc-Regular.otf',
]
LINUX_BOLD = [
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc',
    '/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Bold.otf',
    './fonts/NotoSansSC-Bold.otf',
    './fonts/NotoSansCJKsc-Bold.otf',
]
WIN_REG = r"C:/Windows/Fonts/msyh.ttc"
WIN_BOLD = r"C:/Windows/Fonts/msyhbd.ttc"


def _pick_font(env_key, candidates, fallback):
    p = os.environ.get(env_key)
    if p and os.path.exists(p):
        return p
    for c in candidates:
        if os.path.exists(c):
            return c
    return fallback


def _font_candidates():
    if os.name == 'nt':
        return LINUX_REG + [WIN_REG], LINUX_BOLD + [WIN_BOLD]
    return LINUX_REG + [WIN_REG], LINUX_BOLD + [WIN_BOLD]


_REG_CANDS, _BOLD_CANDS = _font_candidates()
FONT_REG = _pick_font('SHAWN_FONT_REG', _REG_CANDS, WIN_REG)
FONT_BOLD = _pick_font('SHAWN_FONT_BOLD', _BOLD_CANDS, WIN_BOLD)

F_DATE = 96
F_MONTH = 46
F_TIME = 72
F_TITLE = 40
F_BIG = 56
F_BODY = 34
F_SMALL = 27
F_FOOT = 24

BASE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE, '..', 'data')

# ---------- 字体缓存 ----------
_fc = {}
def f(size, bold=False):
    k = (size, bold)
    if k in _fc:
        return _fc[k]
    p = FONT_BOLD if bold else FONT_REG
    try:
        _fc[k] = ImageFont.truetype(p, size)
    except Exception:
        _fc[k] = ImageFont.load_default()
    return _fc[k]

# ---------- 工具 ----------
def tw(draw, s, font):
    b = draw.textbbox((0, 0), s, font=font)
    return b[2] - b[0]

def clip(draw, s, font, max_w):
    if tw(draw, s, font) <= max_w:
        return s
    ell = '…'
    while s and tw(draw, s + ell, font) > max_w:
        s = s[:-1]
    return s + ell

# 自然断句：在标点/空格后切分（零宽 lookbehind，标点保留在前一段末尾）
_SENT_SPLIT = re.compile(r'(?<=[，,。；;！？!?、：:\s])')

def clip_sentence(draw, s, font, max_w):
    """一句话新闻截断：优先在自然标点处收尾，保证整句可读且不超页宽。

    1) 整句能放下 -> 原样返回
    2) 否则按标点分段累加，取能放下的最长前缀（结尾是标点，不再加省略号）
    3) 首段就超宽 / 断出来太短没信息量 -> 退化为硬截断加省略号
    """
    s = ' '.join((s or '').split())
    if not s:
        return s
    if tw(draw, s, font) <= max_w:
        return s
    parts = [p for p in _SENT_SPLIT.split(s) if p]
    out = ''
    idx = 0
    for i, p in enumerate(parts):
        cand = out + p
        if tw(draw, cand, font) <= max_w:
            out = cand
            idx = i + 1
        else:
            break
    # 断句结果要有足够信息量，否则宁可硬截断
    if not out or len(out.strip()) < 6:
        return clip(draw, s, font, max_w)
    # 截在逗号/顿号上、后面还有内容时，用剩余宽度把下一截填满（避免"…放榜，"这种半句）
    if idx < len(parts) and out.rstrip()[-1] not in '。！？!?':
        budget = max_w - tw(draw, out, font)
        # 至少放得下 3 个字 + 省略号，否则补进去只会得到 "To…" 这种碎片
        if budget >= 140:
            frag = clip(draw, ''.join(parts[idx:]), font, budget)
            if frag:
                out = out + frag
    return out.rstrip()

def hline(draw, y, color=GRAY, width=1):
    draw.line([(PAD, y), (SCREEN_W - PAD, y)], fill=color, width=width)

def thickline(draw, y, color=BLACK, width=4):
    draw.line([(PAD, y), (SCREEN_W - PAD, y)], fill=color, width=width)

def fnum(v):
    if v is None: return '?'
    if isinstance(v, float):
        return '%.0f' % v if abs(v) >= 1000 else '%.1f' % v
    return str(v)

def fmt_pct(v):
    if v is None: return '?'
    return '%.1f' % abs(v)

# ---------- 数据 ----------
def fetch_dashboard(url='http://127.0.0.1:8787/api/dashboard'):
    req = urllib.request.Request(url, headers={'User-Agent': 'kindle-dash/1.0'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode('utf-8'))

def load_quotes():
    p = os.path.join(DATA_DIR, 'quotes.txt')
    if os.path.exists(p):
        return [x.strip() for x in open(p, encoding='utf-8').read().splitlines() if x.strip()]
    return []

# ---------- 模块 ----------
def draw_header(draw, d, y):
    now = datetime.now()
    day = now.strftime('%d')
    wd = '一二三四五六日'[now.weekday()]
    mw = '%d月 周%s' % (now.month, wd)
    ts = now.strftime('%H:%M')
    city = (d.get('weather') or {}).get('city') or ''
    fd = f(F_DATE, bold=True)
    draw.text((PAD, y), day, fill=BLACK, font=fd)
    dw = tw(draw, day, fd)
    draw.text((PAD + dw + 24, y + 16), mw, fill=BLACK, font=f(F_MONTH, bold=True))
    ft = f(F_TIME, bold=True)
    tw_s = tw(draw, ts, ft)
    draw.text((SCREEN_W - PAD - tw_s, y - 6), ts, fill=BLACK, font=ft)
    if city:
        fs = f(F_SMALL)
        draw.text((SCREEN_W - PAD - tw(draw, city, fs), y + F_TIME + 6), city, fill=GRAY, font=fs)
    return y + 112

def draw_title(draw, y, text):
    draw.text((PAD, y), text, fill=BLACK, font=f(F_TITLE, bold=True))
    return y + F_TITLE + 8

def draw_news(draw, d, y):
    """今日新闻 · AI：中文一句话，按自然标点断句，绝不超页宽"""
    y = draw_title(draw, y, '今日新闻 · AI')
    items = (d.get('news') or {}).get('items', [])
    ff = f(F_BODY)
    fs = f(F_SMALL)
    if not items:
        draw.text((PAD, y), '新闻源暂不可用', fill=GRAY, font=fs)
        return y + F_SMALL
    n = min(len(items), 3)
    for i in range(n):
        line = '· ' + (items[i].get('title') or '')
        draw.text((PAD, y + i * (F_BODY + 8)), clip_sentence(draw, line, ff, CONTENT_W),
                  fill=BLACK, font=ff)
    return y + n * (F_BODY + 8)

def draw_ai(draw, d, y):
    """AI 额度：WorkBuddy / Claude Code / Codex 三行统一度量衡"""
    # cloud 模式下若本机久未上报，标题直接点明"电脑离线"，不拿旧值假装新鲜
    title = 'AI 额度' if d.get('pcOnline', True) else 'AI 额度 · 电脑离线'
    y = draw_title(draw, y, title)
    q = d.get('quotas', {})
    rows = [
        ('WorkBuddy', q.get('workbuddy', {})),
        ('Claude Code', q.get('claudecode', {})),
        ('Codex', q.get('codex', {}))
    ]
    ff = f(F_BODY)
    fs = f(F_SMALL)
    bar_h, bar_w, gap = 10, 300, 6
    for i, (name, v) in enumerate(rows):
        ry = y + i * (F_BODY + bar_h + gap)
        draw.text((PAD, ry), name, fill=BLACK, font=ff)
        used = v.get('used') if v.get('used') is not None else v.get('used7d')
        cap = v.get('cap')
        rem = v.get('remaining')
        pct = v.get('percent')
        unit = v.get('unit') or ''
        if v.get('ok') and rem is not None and cap is not None:
            val = '%s / %s' % (fnum(rem), fnum(cap))
        elif v.get('ok'):
            val = '%s / %s' % (fnum(used), fnum(cap))
        else:
            val = '未安装' if v.get('error') == 'not-installed' else '不可用'
        # 右侧数值（剩余/总额）
        vx = SCREEN_W - PAD - bar_w - 20 - tw(draw, val, fs)
        draw.text((vx, ry + 4), val, fill=GRAY, font=fs)
        # 进度条（右侧固定宽度，不内嵌文字，e-ink 可读性更好）
        bx = SCREEN_W - PAD - bar_w
        by = ry + 6
        r = bar_h // 2
        draw.rounded_rectangle([bx, by, bx + bar_w, by + bar_h], radius=r, fill=LIGHT_GRAY, outline=BLACK, width=1)
        if v.get('ok') and pct is not None:
            fw = max(bar_h, int(bar_w * (pct or 0) / 100))
            if fw > 2:
                draw.rounded_rectangle([bx, by, bx + fw, by + bar_h], radius=r, fill=BLACK)
        elif not v.get('ok'):
            draw.text((bx + 8, by - 2), '—', fill=GRAY, font=fs)
    return y + len(rows) * (F_BODY + bar_h + gap)

def draw_weather(draw, d, y):
    w = d.get('weather', {})
    y = draw_title(draw, y, '天气')
    if w.get('ok'):
        t1 = '%s°' % fnum(w.get('temp'))
        draw.text((PAD, y), t1, fill=BLACK, font=f(F_BIG, bold=True))
        tw1 = tw(draw, t1, f(F_BIG, bold=True))
        det = '%s  高%s 低%s  湿%s%%' % (w.get('text', ''), fnum(w.get('high')), fnum(w.get('low')), w.get('humidity', '?'))
        draw.text((PAD + tw1 + 24, y + 14), det, fill=GRAY, font=f(F_SMALL))
    else:
        draw.text((PAD, y), '天气不可用', fill=GRAY, font=f(F_SMALL))
    return y + F_BIG

def draw_market(draw, d, y):
    st = (d.get('stocks') or {}).get('items', [])
    y = draw_title(draw, y, '市场')
    ff = f(F_BODY)
    colw = CONTENT_W // 2
    rows = math.ceil(len(st) / 2)
    for i in range(0, len(st), 2):
        ry = y + (i // 2) * (F_BODY + 6)
        for j, s in enumerate(st[i:i+2]):
            x = PAD + j * colw
            if s.get('ok'):
                sign = '+' if (s.get('changePct') or 0) >= 0 else '-'
                cell = '%s %s %s%s%%' % (s.get('label') or s.get('sym'), fnum(s.get('price')), sign, fmt_pct(s.get('changePct')))
            else:
                cell = '%s --' % (s.get('label') or s.get('sym'))
            draw.text((x, ry), clip(draw, cell, ff, colw - 8), fill=BLACK, font=ff)
    return y + rows * (F_BODY + 6)

def draw_clocks(draw, d, y):
    """世界时钟（两列）"""
    y = draw_title(draw, y, '世界时钟')
    cl = (d.get('clocks') or {}).get('items', [])
    ff = f(F_BODY)
    fs = f(F_SMALL)
    colw = CONTENT_W // 2
    if not cl:
        draw.text((PAD, y), '时钟不可用', fill=GRAY, font=fs)
        return y + F_SMALL
    for i in range(0, len(cl), 2):
        ry = y + (i // 2) * (F_BODY + 8)
        for j, c in enumerate(cl[i:i+2]):
            x = PAD + j * colw
            city = c.get('city', '')
            tme = c.get('time', '')[:5]
            draw.text((x, ry), city, fill=BLACK, font=ff)
            cw = tw(draw, city, ff)
            draw.text((x + cw + 12, ry + 2), tme, fill=BLACK, font=ff)
            dw2 = tw(draw, tme, ff)
            date_s = (c.get('date') or '').replace('周', ' 周')
            draw.text((x + cw + dw2 + 24, ry + 6), date_s, fill=GRAY, font=fs)
    return y + math.ceil(len(cl) / 2) * (F_BODY + 8)

def draw_mlb(draw, d, y):
    """MLB · 道奇 / 教士：上一场比分 + 下一场时间（均为北京时间）"""
    y = draw_title(draw, y, 'MLB · 道奇 / 教士')
    items = (d.get('mlb') or {}).get('items', [])
    ff = f(F_BODY)
    fs = f(F_SMALL)
    if not items:
        draw.text((PAD, y), '赛程暂不可用', fill=GRAY, font=fs)
        return y + F_SMALL
    name_w = 80
    col_a = PAD + name_w
    col_b = PAD + name_w + 410

    def mark_of(g):
        # "@勇士" 紧凑；"vs 海盗" 加空格更好读
        return 'vs ' if g.get('home') else '@'

    for i, it in enumerate(items[:2]):
        ry = y + i * (F_BODY + 8)
        draw.text((PAD, ry), it.get('cn', ''), fill=BLACK, font=f(F_BODY, bold=True))
        last = it.get('last') or {}
        nxt = it.get('next') or {}
        if last:
            s = '%s %s%s %s-%s' % (last.get('date', ''), mark_of(last), last.get('opp', ''),
                                   last.get('us', 0), last.get('them', 0))
            draw.text((col_a, ry), s, fill=GRAY, font=ff)
            res = '胜' if last.get('win') else '负'
            # 胜=黑，负=灰：e-ink 上靠明度区分，不用颜色
            draw.text((col_a + tw(draw, s, ff) + 12, ry), res,
                      fill=BLACK if last.get('win') else GRAY, font=f(F_BODY, bold=True))
        else:
            draw.text((col_a, ry), '无近期战报', fill=GRAY, font=fs)
        if nxt:
            s2 = '→ %s %s %s%s' % (nxt.get('date', ''), nxt.get('time', ''),
                                   mark_of(nxt), nxt.get('opp', ''))
            draw.text((col_b, ry), clip(draw, s2, ff, SCREEN_W - PAD - col_b), fill=BLACK, font=ff)
    return y + min(len(items), 2) * (F_BODY + 8)

def draw_quote(draw, d, y, quotes):
    y = draw_title(draw, y, '今日一句')
    if not quotes:
        draw.text((PAD, y), '（编辑 data/quotes.txt）', fill=GRAY, font=f(F_SMALL))
        return y + F_SMALL
    ff = f(F_BODY)
    q = quotes[datetime.now().timetuple().tm_yday % len(quotes)]
    if ' —— ' in q:
        text, src = q.split(' —— ', 1)
    elif '—' in q:
        text, src = q.split('—', 1)
    else:
        text, src = q, ''
    line = clip(draw, text, ff, CONTENT_W - 80)
    if src:
        line = clip(draw, line + '  — ' + src, ff, CONTENT_W)
    draw.text((PAD, y), line, fill=BLACK, font=ff)
    return y + F_BODY + 6

def draw_footer(draw, d, y, offline=False, last_ok=None):
    hline(draw, y, GRAY, 1)
    y += 12
    now = datetime.now().strftime('%H:%M')
    txt = ('Shawn Kanban · 离线 · 最后 %s · 顶部下滑返回' % (last_ok or '?')) if offline \
        else ('Shawn Kanban · 更新 %s · 顶部下滑返回' % now)
    draw.text((PAD, y), txt, fill=GRAY, font=f(F_FOOT))
    return y + F_FOOT

# ---------- 主流程 ----------
def render(d, out_path=None):
    img = Image.new('L', (SCREEN_W, SCREEN_H), WHITE)
    draw = ImageDraw.Draw(img)
    quotes = load_quotes()

    y = PAD
    y = draw_header(draw, d, y)
    y += 10
    thickline(draw, y, BLACK, 4)
    y += 16

    mods = [
        lambda y: draw_news(draw, d, y),
        lambda y: draw_ai(draw, d, y),
        lambda y: draw_weather(draw, d, y),
        lambda y: draw_market(draw, d, y),
        lambda y: draw_clocks(draw, d, y),
        lambda y: draw_mlb(draw, d, y),
        lambda y: draw_quote(draw, d, y, quotes)
    ]
    for fn in mods:
        y = fn(y)
        hline(draw, y + 4, GRAY, 1)
        y += 14
    y = draw_footer(draw, d, y)

    print('[render] final_y=%d screen_h=%d margin=%d' % (y, SCREEN_H, SCREEN_H - y), file=sys.stderr, flush=True)
    out = img.convert('1', dither=Image.Dither.FLOYDSTEINBERG)
    if out_path:
        out.save(out_path)
        print('saved', out_path, file=sys.stderr, flush=True)
    else:
        out.save(sys.stdout.buffer, 'PNG')
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out')
    ap.add_argument('--data')
    ap.add_argument('--url', default='http://127.0.0.1:8787/api/dashboard')
    a = ap.parse_args()
    # CI 上字体找错会渲染成方块，打出来便于排查
    print('[render] font_reg=%s%s' % (FONT_REG, '' if os.path.exists(FONT_REG) else '  <-- 缺失!'),
          file=sys.stderr, flush=True)
    print('[render] font_bold=%s%s' % (FONT_BOLD, '' if os.path.exists(FONT_BOLD) else '  <-- 缺失!'),
          file=sys.stderr, flush=True)
    d = json.load(open(a.data, encoding='utf-8')) if a.data else fetch_dashboard(a.url)
    render(d, a.out)

if __name__ == '__main__':
    main()
