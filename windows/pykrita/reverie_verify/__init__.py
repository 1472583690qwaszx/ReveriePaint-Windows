# SPDX-License-Identifier: GPL-3.0-or-later
"""PyKrita 加载探针。

这个模块没有任何界面：被 PyKrita 成功 import 就说明
「构建期探测 → kritapykrita 插件 → python/ 运行时 → krita 模块 → pykrita 包 → 插件目录」
整条链路是通的。05-verify.ps1 靠它写出标记文件来判定。
"""

import os
import sys
import time
from pathlib import Path

PROBE_NAME = "reverie-pykrita-probe.txt"


def _write_probe():
    appdata = os.environ.get("APPDATA")
    base = Path(appdata) if appdata else Path.home() / "AppData" / "Roaming"
    target = base / "krita" / PROBE_NAME

    lines = [
        "ok=true",
        "time=" + time.strftime("%Y-%m-%d %H:%M:%S"),
        "python=" + sys.version.split()[0],
        "executable=" + (sys.executable or "(embedded)"),
    ]

    try:
        from PyQt6.QtCore import PYQT_VERSION_STR, QT_VERSION_STR

        lines.append("pyqt=PyQt6 %s (Qt %s)" % (PYQT_VERSION_STR, QT_VERSION_STR))
    except Exception as exc:
        try:
            from PyQt5.QtCore import PYQT_VERSION_STR, QT_VERSION_STR

            lines.append("pyqt=PyQt5 %s (Qt %s)" % (PYQT_VERSION_STR, QT_VERSION_STR))
        except Exception:
            lines.append("pyqt=IMPORT_FAILED %r" % (exc,))

    try:
        import krita

        lines.append("krita_module=" + str(getattr(krita, "__file__", "(builtin)")))
        lines.append("krita_version=" + str(getattr(krita, "__version__", "unknown")))
    except Exception as exc:
        lines.append("krita_module=IMPORT_FAILED %r" % (exc,))

    try:
        import pykrita

        lines.append("pykrita_module=" + str(getattr(pykrita, "__file__", "(builtin)")))
    except Exception as exc:
        lines.append("pykrita_module=IMPORT_FAILED %r" % (exc,))

    root = None
    try:
        root = Path(krita.__file__).resolve().parents[3]
    except Exception:
        pass
    if root:
        lines.append("app_root=" + str(root))
        for name in ("share/krita/pykrita", "lib/krita-python-libs", "lib/site-packages", "python"):
            sub = root / name
            lines.append("path.%s=%s" % (name.replace("/", "_"), "yes" if sub.exists() else "no"))

    lines.append("plugins_user=" + str(base / "krita" / "pykrita"))

    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    except Exception as exc:
        print("reverie_verify: cannot write probe: %r" % (exc,), file=sys.stderr)


_write_probe()
