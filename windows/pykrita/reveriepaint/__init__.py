# SPDX-License-Identifier: GPL-3.0-or-later
"""ReveriePaint 随包插件入口。

被 PyKrita 导入时做两件事：
1. 往主窗口注册「ReveriePaint」停靠面板（Docker）；
2. 后台把仓库里的内置笔刷/笔尖/图案导入到用户资源目录（只做一次）。
"""

from krita import DockWidgetFactory, DockWidgetFactoryBase, Krita

from . import assets
from .docker import ReveriePaintDocker

PANEL_ID = "reveriepaint_panel"

_krita = Krita.instance()
_krita.addDockWidgetFactory(
    DockWidgetFactory(PANEL_ID, DockWidgetFactoryBase.DockPosition.DockRight, ReveriePaintDocker)
)

# 资产导入要拷 ~54MB 文件，放到后台线程，别卡住 Krita 启动
assets.ensure_assets_in_background()
