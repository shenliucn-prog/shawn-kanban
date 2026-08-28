# -*- coding: utf-8 -*-
"""KOReader 插件 Lua 语法检查（Windows 主机上跑，不需要 Kindle）。

KOReader 自带 /mnt/us/koreader/luajit 是 ARM 版，Windows 上执行不了。
这里用 lupa（Python 内嵌 Lua）编译源码，只查语法、不执行，
因此在 require("ui/widget/...") 等 KOReader 模块缺失的情况下也能校验。

用法:
    python tools/check_lua.py                 # 检查默认插件
    python tools/check_lua.py path/to/x.lua   # 检查指定文件
退出码: 0=通过, 1=语法错误, 2=环境缺 lupa
"""
import os
import sys

DEFAULT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'KindleDash.koplugin', 'main.lua'
)

CHECK_FN = (
    'function(s) local fn, e = load(s) '
    'return { ok = (fn ~= nil), err = tostring(e or "") } end'
)


def check(path):
    src = open(path, encoding='utf-8').read()
    from lupa import LuaRuntime
    r = LuaRuntime().eval(CHECK_FN)(src)
    return bool(r['ok']), str(r['err'])


def main():
    paths = sys.argv[1:] or [DEFAULT]
    bad = 0
    for p in paths:
        p = os.path.abspath(p)
        if not os.path.exists(p):
            print('MISSING  %s' % p)
            bad += 1
            continue
        ok, err = check(p)
        if ok:
            print('OK       %s' % p)
        else:
            print('ERROR    %s\n%s' % (p, err))
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except ImportError:
        print('需要 lupa: python -m pip install lupa', file=sys.stderr)
        sys.exit(2)
