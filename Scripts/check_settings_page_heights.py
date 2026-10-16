#!/usr/bin/env python3
"""量十个设置页的自然高度，超过窗口上限（1074 pt）就退出码 1 —— 规则 10 的机械检查。

用法：
    python3 Scripts/check_settings_page_heights.py [--app /path/to/KatiKati.app]

高度不是这份脚本算的：它用 `DOCK_SETTINGS_PAGE_HEIGHT=1` 启动一次 app，app 用**给窗口量高的同一条
路径**（`SettingsWindowController.naturalContentHeight`，见 `SettingsPageHeightProbe`）量完十页后
打印 `SETTINGS_CLAMP <上限>` 与 `SETTINGS_PAGE <标签> <高度>`，然后退出。

判据：每页**内容**高度 ≤ min(986, SETTINGS_CLAMP)。986 = 窗口 1074 pt − 88 pt（标题栏 + 工具栏，
十页实测一致，与 `evidence/2026-10-15-close-out` 的算法同源）；1074 是文档里那个「窗口高过它就滚动」
的数（参考机器 `visibleFrame` 1074）。在更小的屏幕上 `SettingsWindowController` 自己的上限
（`SETTINGS_CLAMP`，`visibleFrame − 80`）更低，那时按机器的算 —— 两种情况都是「这一页放不下，
用户得滚」，也就是规则 10 要拦的东西。

退出码：0 全过；1 有页超出；2 跑不起来（没构建 / 探测没输出）。
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REFERENCE_CONTENT_LIMIT = 986
DEFAULT_APPS = [
    'build/DerivedData/Build/Products/Debug/KatiKati.app',
    'build/DerivedData/Build/Products/Release/KatiKati.app',
    '/Applications/KatiKati.app',
]
PAGE = re.compile(r'^SETTINGS_PAGE (\S+) ([0-9.]+)$')
CLAMP = re.compile(r'^SETTINGS_CLAMP ([0-9.]+)$')


def find_app(explicit: str | None) -> pathlib.Path | None:
    candidates = [pathlib.Path(explicit)] if explicit else [ROOT / p for p in DEFAULT_APPS]
    for path in candidates:
        if (path / 'Contents/MacOS/KatiKati').is_file():
            return path
    return None


def measure(app: pathlib.Path) -> tuple[float | None, list[tuple[str, float]], str]:
    try:
        run = subprocess.run(
            [str(app / 'Contents/MacOS/KatiKati')],
            capture_output=True, text=True, timeout=120,
            env={**os.environ, 'DOCK_SETTINGS_PAGE_HEIGHT': '1'},
        )
    except subprocess.TimeoutExpired:
        return None, [], '探测超时（120s）—— 那条 switch 还在吗？'
    clamp, pages = None, []
    for line in run.stdout.splitlines():
        if (m := CLAMP.match(line.strip())):
            clamp = float(m.group(1))
        elif (m := PAGE.match(line.strip())):
            pages.append((m.group(1), float(m.group(2))))
    if not pages:
        tail = (run.stdout + run.stderr).strip().splitlines()[-3:]
        return clamp, [], '探测没有输出页面高度：' + ' / '.join(tail)
    return clamp, pages, ''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', help='要量的 KatiKati.app（默认找 build/DerivedData 里的 Debug/Release）')
    args = parser.parse_args()

    app = find_app(args.app)
    if app is None:
        print('❌ 没找到 KatiKati.app —— 先构建（Scripts/build_and_run.sh），或用 --app 指定')
        return 2

    clamp, pages, error = measure(app)
    if error:
        print(f'❌ {error}')
        return 2

    limit = min(REFERENCE_CONTENT_LIMIT, clamp) if clamp is not None else REFERENCE_CONTENT_LIMIT
    over = [(name, h) for name, h in pages if h > limit]
    print(f'app：{app}')
    print(f'上限 {limit:.0f} pt 内容高（窗口 1074 pt；参考值 {REFERENCE_CONTENT_LIMIT}'
          + (f'，本机窗口上限 {clamp:.0f}' if clamp is not None else '') + '）')
    for name, height in sorted(pages, key=lambda p: -p[1]):
        print(f'  {"❌" if height > limit else "  "} {name:<20} {height:>7.1f} pt'
              f'   余量 {limit - height:>6.1f}')
    if len(pages) < 10:
        print(f'❌ 只量到 {len(pages)} 页（十个标签页都该有数）—— 探测漏页了')
        return 1
    if over:
        print('❌ 这些页高过窗口就会滚动：' + '、'.join(f'{n}（{h:.0f} pt）' for n, h in over))
        print('   按 Docs/SETTINGS.md 规则 5（合并卡片 / 配对窄行 / 长列表折叠）腾地方，别删控件。')
        return 1
    print(f'✅ 十页都放得下，最紧的一页余 {limit - max(h for _, h in pages):.1f} pt')
    return 0


if __name__ == '__main__':
    sys.exit(main())
