# SPDX-License-Identifier: GPL-3.0-or-later
"""「ReveriePaint」停靠面板：笔刷导入、目录跳转、环境诊断。"""

from krita import DockWidget

try:  # Krita 6 用 PyQt6；保留 PyQt5 分支便于在 5.x 上调试
    from PyQt6.QtCore import QTimer, QUrl
    from PyQt6.QtGui import QDesktopServices
    from PyQt6.QtWidgets import (
        QDialog,
        QHBoxLayout,
        QLabel,
        QPlainTextEdit,
        QPushButton,
        QVBoxLayout,
        QWidget,
    )
except ImportError:  # pragma: no cover
    from PyQt5.QtCore import QTimer, QUrl
    from PyQt5.QtGui import QDesktopServices
    from PyQt5.QtWidgets import (
        QDialog,
        QHBoxLayout,
        QLabel,
        QPlainTextEdit,
        QPushButton,
        QVBoxLayout,
        QWidget,
    )

from . import assets, diagnostics


class ReveriePaintDocker(DockWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ReveriePaint")
        self._build_ui()
        self._refresh()

    # ---- UI ----
    def _build_ui(self):
        root = QWidget(self)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        self._status = QLabel("正在读取资源状态…", root)
        self._status.setWordWrap(True)
        layout.addWidget(self._status)

        row1 = QHBoxLayout()
        self._btn_import = QPushButton("导入/更新内置笔刷", root)
        self._btn_import.clicked.connect(self._on_import)
        row1.addWidget(self._btn_import)

        self._btn_reload = QPushButton("刷新状态", root)
        self._btn_reload.clicked.connect(self._refresh)
        row1.addWidget(self._btn_reload)
        layout.addLayout(row1)

        row2 = QHBoxLayout()
        self._btn_plugins = QPushButton("打开 Python 插件目录", root)
        self._btn_plugins.clicked.connect(lambda: self._open_dir(assets.user_resource_dir() / "pykrita"))
        row2.addWidget(self._btn_plugins)

        self._btn_res = QPushButton("打开笔刷资源目录", root)
        self._btn_res.clicked.connect(lambda: self._open_dir(assets.user_resource_dir()))
        row2.addWidget(self._btn_res)
        layout.addLayout(row2)

        row3 = QHBoxLayout()
        self._btn_diag = QPushButton("诊断报告", root)
        self._btn_diag.clicked.connect(self._on_diagnostics)
        row3.addWidget(self._btn_diag)
        layout.addLayout(row3)

        layout.addStretch(1)
        self.setWidget(root)

    # ---- 行为 ----
    def _open_dir(self, path):
        try:
            path.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def _refresh(self):
        s = assets.summary()
        state = s.get("state", {})
        if state.get("running"):
            self._status.setText("正在导入内置笔刷…（可继续作画，完成后刷新）")
            return
        src = s.get("source")
        text = (
            "笔刷预设 %d 个 · 笔尖 %d 个 · 图案 %d 个\n资源目录：%s"
            % (s.get("paintoppresets", 0), s.get("brushes", 0), s.get("patterns", 0), s.get("dest"))
        )
        if not src:
            text += "\n未找到内置资产源，导入功能不可用。"
        last = state.get("last")
        if last:
            if last.get("ok"):
                if last.get("skipped"):
                    text += "\n上次导入：已是最新"
                else:
                    copied = last.get("copied", {})
                    text += "\n上次导入：%s" % (", ".join("%s +%d" % (k, v) for k, v in copied.items()) or "无新增")
            else:
                text += "\n上次导入失败：%s" % last.get("reason", "未知原因")
        self._status.setText(text)

    def _on_import(self):
        self._btn_import.setEnabled(False)
        self._status.setText("正在导入，请稍候…")

        def done(result):
            QTimer.singleShot(0, lambda: self._after_import(result))

        if not assets.ensure_assets_async(force=True, on_done=done):
            self._status.setText("已有导入任务在进行中")

    def _after_import(self, result):
        self._btn_import.setEnabled(True)
        self._refresh()
        if result and not result.get("ok"):
            self._status.setText("导入出现问题：%s" % result.get("reason", result))

    def _on_diagnostics(self):
        text, path = diagnostics.write_report()
        dialog = QDialog(self)
        dialog.setWindowTitle("ReveriePaint 诊断")
        dialog.resize(760, 520)
        layout = QVBoxLayout(dialog)
        view = QPlainTextEdit(dialog)
        view.setReadOnly(True)
        view.setPlainText(text)
        layout.addWidget(view)
        if path:
            hint = QLabel("报告已写入：%s" % path, dialog)
            hint.setWordWrap(True)
            layout.addWidget(hint)
        close = QPushButton("关闭", dialog)
        close.clicked.connect(dialog.accept)
        layout.addWidget(close)
        dialog.exec()

    # Krita 的 DockWidget 必须实现这个钩子
    def canvasChanged(self, canvas):
        return
