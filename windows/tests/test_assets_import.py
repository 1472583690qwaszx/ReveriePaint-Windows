# 独立测试：用真实资产验证 assets.ensure_assets 的导入与幂等
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 不需要 Krita、不需要 PyQt：assets.py 只依赖标准库。
#   python windows\tests\test_assets_import.py

import importlib.util
import tempfile
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
WINDOWS_DIR = HERE.parents[1]
REPO_ROOT = WINDOWS_DIR.parent

ASSET_CANDIDATES = [
    REPO_ROOT / "app" / "src" / "main" / "assets",
    REPO_ROOT / "work" / "ReveriePaint-main" / "app" / "src" / "main" / "assets",
]


def load_assets_module():
    path = WINDOWS_DIR / "pykrita" / "reveriepaint" / "assets.py"
    spec = importlib.util.spec_from_file_location("rp_assets", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    source = next((p for p in ASSET_CANDIDATES if (p / "paintoppresets").is_dir()), None)
    if source is None:
        print("SKIP: 找不到 app/src/main/assets（把 windows/ 放到仓库根再跑）")
        return 0

    assets = load_assets_module()
    tmp = Path(tempfile.mkdtemp(prefix="reverie-assets-"))
    assets.asset_source = lambda: source
    assets.user_resource_dir = lambda: tmp / "krita"

    first = assets.ensure_assets(force=True)
    counts = {kind: assets.count_resources(kind) for kind in assets.RESOURCE_KINDS}
    print("source:", source)
    print("copied:", first.get("copied"), "errors:", first.get("errors"))
    print("counts:", counts)

    assert first["ok"], "首次导入应成功"
    assert counts["paintoppresets"] >= 250, counts
    assert counts["brushes"] >= 200, counts
    assert counts["patterns"] >= 100, counts

    second = assets.ensure_assets()
    assert second.get("skipped"), "第二次导入应判定为已是最新并跳过"
    print("idempotent: OK")
    print("marker:", (tmp / "krita" / assets.MARKER_NAME).is_file())
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
