# SPDX-License-Identifier: GPL-3.0-or-later
"""内置笔刷 / 笔尖 / 图案导入。

源目录：<应用根>/share/reveriepaint/assets（或环境变量 REVERIE_ASSET_DIR）
目标目录：%APPDATA%\\krita\\{paintoppresets,brushes,patterns}

为什么拷到用户资源目录而不是安装目录：
- Krita 的笔刷预设按用户资源库索引，安装目录的 share/krita 属于"只读资源"，
  升级/卸载会整块替换，用户后续对笔刷的增删也会丢；
- .kpp 与笔尖是文件名强引用，两边必须一起导入，放在同一层用户目录最省心。
"""

import json
import os
import shutil
import sys
import threading
import time
from pathlib import Path

MARKER_NAME = ".reverie_assets.json"
MARKER_VERSION = 1

# Krita 的资源类型目录名 -> 关注的扩展名
RESOURCE_KINDS = {
    "paintoppresets": (".kpp", ".myb"),
    "brushes": (".gbr", ".gih", ".png", ".svg"),
    "patterns": (".pat", ".png"),
}

_state = {"running": False, "last": None}
_lock = threading.Lock()


def app_root():
    """定位应用根目录（含 bin/ 与 share/ 的那一层）。"""
    env = os.environ.get("REVERIE_ROOT")
    if env and Path(env).is_dir():
        return Path(env)
    try:
        import krita  # PyKrita 的 python 包

        # <root>/lib/krita-python-libs/krita/__init__.py
        candidate = Path(krita.__file__).resolve().parents[3]
        if (candidate / "bin").is_dir() or (candidate / "share").is_dir():
            return candidate
    except Exception:
        pass
    return None


def asset_source():
    env = os.environ.get("REVERIE_ASSET_DIR")
    if env and Path(env).is_dir():
        return Path(env)
    root = app_root()
    if root is not None:
        candidate = root / "share" / "reveriepaint" / "assets"
        if candidate.is_dir():
            return candidate
    return None


def user_resource_dir():
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "krita"
    return Path.home() / "AppData" / "Roaming" / "krita"


def count_resources(kind, directory=None):
    directory = Path(directory) if directory else user_resource_dir() / kind
    if not directory.is_dir():
        return 0
    exts = RESOURCE_KINDS.get(kind, ())
    return sum(1 for p in directory.iterdir() if p.is_file() and p.suffix.lower() in exts)


def summary():
    result = {}
    for kind in RESOURCE_KINDS:
        result[kind] = count_resources(kind)
    src = asset_source()
    result["source"] = str(src) if src else None
    result["dest"] = str(user_resource_dir())
    result["state"] = dict(_state)
    marker = user_resource_dir() / MARKER_NAME
    if marker.is_file():
        try:
            result["marker"] = json.loads(marker.read_text(encoding="utf-8"))
        except Exception:
            result["marker"] = None
    return result


def ensure_assets(force=False):
    """把内置资源导入用户目录；已导入且源未变化时直接返回。"""
    src = asset_source()
    if src is None:
        return {"ok": False, "reason": "找不到资产源（share/reveriepaint/assets 或 REVERIE_ASSET_DIR）"}

    dest_root = user_resource_dir()
    marker_path = dest_root / MARKER_NAME
    if marker_path.is_file() and not force:
        try:
            marker = json.loads(marker_path.read_text(encoding="utf-8"))
            if marker.get("version") == MARKER_VERSION and marker.get("source") == str(src):
                return {"ok": True, "skipped": True, "marker": marker}
        except Exception:
            pass

    copied = {}
    skipped = 0
    errors = []
    for kind, exts in RESOURCE_KINDS.items():
        src_dir = src / kind
        if not src_dir.is_dir():
            continue
        dst_dir = dest_root / kind
        dst_dir.mkdir(parents=True, exist_ok=True)
        n = 0
        for item in src_dir.iterdir():
            if not item.is_file() or item.suffix.lower() not in exts:
                continue
            target = dst_dir / item.name
            try:
                if target.is_file() and target.stat().st_size == item.stat().st_size:
                    skipped += 1
                    continue
                shutil.copy2(item, target)
                n += 1
            except Exception as exc:  # 单个文件失败不影响其它
                errors.append(f"{item.name}: {exc}")
        copied[kind] = n

    marker = {
        "version": MARKER_VERSION,
        "source": str(src),
        "time": time.strftime("%Y-%m-%d %H:%M:%S"),
        "copied": copied,
        "skipped": skipped,
        "errors": errors[:20],
    }
    try:
        dest_root.mkdir(parents=True, exist_ok=True)
        marker_path.write_text(json.dumps(marker, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as exc:
        errors.append(f"marker: {exc}")

    return {"ok": not errors or len(errors) < 5, "copied": copied, "skipped": skipped,
            "errors": errors, "dest": str(dest_root)}


def ensure_assets_async(force=False, on_done=None):
    """后台导入，避免阻塞 Krita 启动。"""
    with _lock:
        if _state["running"]:
            return False
        _state["running"] = True

    def work():
        try:
            _state["last"] = ensure_assets(force=force)
        except Exception as exc:
            _state["last"] = {"ok": False, "reason": repr(exc)}
            print("reveriepaint: asset import failed:", exc, file=sys.stderr)
        finally:
            _state["running"] = False
            if on_done:
                try:
                    on_done(_state["last"])
                except Exception:
                    pass

    threading.Thread(target=work, name="reverie-assets", daemon=True).start()
    return True


def ensure_assets_in_background():
    return ensure_assets_async()
