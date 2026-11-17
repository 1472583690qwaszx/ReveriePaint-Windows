# ReveriePaint for Windows

把 [ReveriePaint](https://github.com/LanRhyme/ReveriePaint)（基于 Krita 内核的 Android 绘画应用）移植到 Windows 桌面：Krita 6.0.4 外壳 + 完整 PyKrita 插件体系。

## 产物

Actions → **Windows build and installer** → 运行页的 `ReveriePaint-Windows` 附件：

- `ReveriePaint.zip`：便携版，解压即用（`bin/krita.exe`，`ReveiePaint.cmd` 启动）
- `ReveriePaint-*-setup.exe`：Inno Setup 安装包（可选 .kra 关联、桌面快捷方式）
- `build.log`：完整编译日志

## 流水线做了什么

1. 装 Python 3.13 / llvm-mingw 20251118 / Ninja / CMake 3.31（Krita 官方 Windows 工具链口径，不用 MSVC）
2. 校验并展开移植包（构建脚本、17 条补丁、`0005b` PSD 重基补丁、PyKrita 插件、Inno 脚本）
3. 克隆 Krita `v6.0.4` + `krita-deps-management` + `krita-ci-utilities`，跑 `setup-env.py --full-krita-env` 拉预编译依赖
4. 按依赖顺序打 10 条桌面补丁 + `0005b`，每条单独提交
5. `cmake -G Ninja -DCMAKE_INSTALL_PREFIX=... -DBUILD_WITH_QT6=ON -DALLOW_UNSTABLE=QT6` → `ninja install`
6. 用 Krita 官方 `package-complete.py` 合包（内嵌 Python + PyQt6 + `krita-python-libs`），注入笔刷资产
7. `iscc` 出安装包，上传产物

首次运行约 2~4 小时（4 核 runner），超时上限 360 分钟。

## 许可

Krita 与 ReveriePaint 均为 GPL-3.0-or-later；本仓库不含 Krita 源码，构建时从 KDE 官方仓库拉取。
