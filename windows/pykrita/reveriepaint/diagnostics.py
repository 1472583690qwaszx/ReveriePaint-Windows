# SPDX-License-Identifier: GPL-3.0-or-later
"""环境诊断：出问题时先看这份报告。"""

import platform
import sys
import time
from pathlib import Path

from . import assets


def _pyqt_info():
    try:
        from PyQt6.QtCore import PYQT_VERSION_STR, QT_VERSION_STR

        return "PyQt6 %s (Qt %s)" % (PYQT_VERSION_STR, QT_VERSION_STR)
    except Exception:
        pass
    try:
        from PyQt5.QtCore import PYQT_VERSION_STR, QT_VERSION_STR

        return "PyQt5 %s (Qt %s)" % (PYQT_VERSION_STR, QT_VERSION_STR)
    except Exception as exc:
        return "无法导入 PyQt: %r" % (exc,)


def _krita_info():
    try:
        import krita

        return {
            "module": str(getattr(krita, "__file__", "?")),
            "version": str(getattr(krita, "__version__", "unknown")),
        }
    except Exception as exc:
        return {"module": "导入失败: %r" % (exc,), "version": "?"}


def _count_desktops(directory):
    directory = Path(directory)
    if not directory.is_dir():
        return 0
    return sum(1 for p in directory.iterdir() if p.is_file() and p.suffix == ".desktop")


def collect_text():
    root = assets.app_root()
    src = assets.asset_source()
    user_dir = assets.user_resource_dir()
    krita = _krita_info()
    summary = assets.summary()

    lines = []
    lines.append("ReveriePaint / PyKrita 诊断报告")
    lines.append("生成时间: " + time.strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("")
    lines.append("[运行环境]")
    lines.append("  Python: %d.%d.%d" % sys.version_info[:3])
    lines.append("  解释器: %s" % (sys.executable or "(内嵌)"))
    lines.append("  平台: %s %s" % (platform.system(), platform.machine()))
    lines.append("  PyQt: %s" % _pyqt_info())
    lines.append("  krita 模块: %s" % krita["module"])
    lines.append("  krita 版本: %s" % krita["version"])
    lines.append("  应用根目录: %s" % (root if root else "(未能判定)"))
    lines.append("")
    lines.append("[资源]")
    lines.append("  资产源: %s" % (src if src else "(未找到)"))
    lines.append("  用户资源目录: %s" % user_dir)
    for kind in ("paintoppresets", "brushes", "patterns"):
        lines.append("  %s: %d 个" % (kind, summary.get(kind, 0)))
    marker = summary.get("marker")
    if marker:
        lines.append("  上次导入: %s 复制=%s 跳过=%s" % (
            marker.get("time"), marker.get("copied"), marker.get("skipped")))
        if marker.get("errors"):
            lines.append("  导入错误: %s" % marker.get("errors")[:5])
    else:
        lines.append("  上次导入: 尚未导入")
    lines.append("")
    lines.append("[Python 插件目录]")
    install_plugin_dir = (root / "share" / "krita" / "pykrita") if root else None
    if install_plugin_dir:
        lines.append("  内置: %s（%d 个 .desktop）" % (install_plugin_dir, _count_desktops(install_plugin_dir)))
    lines.append("  用户: %s（%d 个 .desktop）" % (user_dir / "pykrita", _count_desktops(user_dir / "pykrita")))
    lines.append("")
    lines.append("[sys.path 中与应用相关的条目]")
    for entry in sys.path:
        if not entry:
            continue
        if root and str(root).lower() in entry.lower():
            lines.append("  " + entry)
    lines.append("")
    lines.append("[已加载的 krita 相关模块]")
    for name in sorted(sys.modules):
        if name.startswith(("krita", "PyKrita", "pykrita")) or name == "reveriepaint":
            module = sys.modules[name]
            lines.append("  %s -> %s" % (name, getattr(module, "__file__", "(builtin)")))
    return "\n".join(lines) + "\n"


def write_report():
    text = collect_text()
    user_dir = assets.user_resource_dir()
    try:
        user_dir.mkdir(parents=True, exist_ok=True)
        path = user_dir / "reveriepaint-diagnostics.txt"
        path.write_text(text, encoding="utf-8")
    except Exception:
        path = None
    return text, path
