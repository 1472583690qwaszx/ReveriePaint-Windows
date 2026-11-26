# 把 Krita 原生的 Python 插件系统接回来

Android 版把 PyKrita 整块丢了，不是"没开开关"，而是**整条链路都不存在**：

- 引擎只链 `libkritaimage` / `libkritapigment` / `libkritaui` 等核心库，构建里没有 `plugins/python`；
- 引擎按铁律只跑 `QCoreApplication`，没有任何 `QWidget`；
- 构建产物里没有 Python 运行时、没有 PyQt、没有 SIP 绑定，也没有 `kritapykrita` 插件 DLL。

Windows 版走 Krita 桌面构建，这条链路是**原生自带**的，不需要我们自己写 Python 绑定。要做的是"让它被探测到、被编进去、被正确装进发行目录、并验证它真的加载"。

---

## 1. 构建期：三个开关决定 PyKrita 是否存在

Krita 源码里的判定（已对照 v6.0.4 核对）：

```cmake
# plugins/CMakeLists.txt:14
if ((HAVE_PYQT5 OR HAVE_PYQT6) AND HAVE_SIP AND HAVE_PYTHONLIBS)
    add_subdirectory( python )      # 20+ 个内置 Python 插件（tenbrushes/tencripts/scripter/...）
endif()

# plugins/extensions/pykrita/CMakeLists.txt:1
if (HAVE_PYQT${QT_MAJOR_VERSION} AND HAVE_SIP AND HAVE_PYTHONLIBS)
    add_subdirectory(sip)          # krita 的 SIP 绑定
    add_subdirectory(plugin)       # kritapykrita 插件 DLL（含 PythonPluginManager）
    add_subdirectory(kritarunner)  # 给外部脚本用的 kritarunner.exe
endif()
```

这三个变量由根 `CMakeLists.txt` 的探测结果决定：

| 变量 | 来源 | Windows 注意点 |
|---|---|---|
| `HAVE_PYTHONLIBS` | `find_package(Python 3.8 COMPONENTS Development Interpreter)` + `PythonLibrary`，并用 `TestCompileLinkPythonLibs` 真编一段 `Py_InitializeEx` 验证可链接 | Windows 走 `Python_FIND_STRATEGY LOCATION`；**必须 64 位、版本 3.13**（Krita 6 分支口径，3.10 是 5.2 旧分支） |
| `HAVE_SIP` | `find_package(SIP "4.19.13")` | 由预编译依赖提供 |
| `HAVE_PYQT6` | `find_package(PyQt6 "6.7.0")` | 由预编译依赖提供；Qt 5 分支则找 PyQt5 |

所以**"加回 Python 插件"的第一步是让配置阶段这三个都为真**。`03-build.ps1` 会在配置日志里显式检查：

```
-- Found Python: ... (found version "3.13.x")
-- Found SIP: ...
-- Found PyQt6: ...
```

三个缺任何一个，`share\krita\pykrita` 里就只会有零散文件，`kritapykrita.dll` 也不会生成。见 §5 排错。

---

## 2. 运行期：路径与目录（Windows 特有）

PyKrita 在 `plugins/extensions/pykrita/plugin/utilities.cpp` 的 `Python::setPath()` 里手工拼 `sys.path`，**Windows 分支**要求：

```
<应用根目录>/
├── python/                     # 嵌入式 Python 3.13（必须有，否则直接 "Bundled Python not found"）
│   ├── python313.zip
│   └── ...
├── lib/
│   ├── krita-python-libs/      # SIP 生成的 krita 包 + libkritapykrita 的 python 部分
│   │   └── krita/{__init__.py, api.py, ...}
│   └── site-packages/          # PyQt6 / sip 等
└── share/
    └── krita/
        ├── pykrita/            # Python 插件：<模块名>.py + kritapykrita_<模块名>.desktop
        └── ...
```

对应源码行为：

- `python/` 是从 `<root>/python` 找的，命中后会把 `python313.zip` 和该目录本身加进 `sys.path`（`Q_OS_WIN` 分支）；
- `krita-python-libs` 与 `site-packages` 由 `findKritaPythonLibsPath()` 在 `<root>/lib*`、`<root>/share`、`<root>/Frameworks` 下逐层查找；
- 官方 `packaging/windows/package-complete.py` 正是按这个布局把 `_install/python`、`_install/lib/site-packages`、`lib/krita-python-libs` 合并进发行目录，并删掉 `python.exe` / `pythonw.exe`、清掉 pip/setuptools 之类不需要的包。`04-stage-portable.ps1` 直接调用它，不自己造一套。

用户侧的插件目录（可写、优先级高于安装目录）：

```
%APPDATA%\krita\pykrita\
├── myplugin.py
├── kritapykrita_myplugin.desktop
└── myplugin/            # 若插件是目录形式
```

`KoResourcePaths::findAllAssets("data", "pykrita/*desktop")` 会递归扫安装目录与用户目录，所以**只要把 `.py` + `.desktop` 丢进 `%APPDATA%\krita\pykrita` 就能加载**，不需要改任何配置。这也是我们随包插件的部署方式。

### 插件描述文件格式

```ini
[Desktop Entry]
Name=My Plugin
Comment=...
Type=Service
ServiceTypes=Krita/PythonPlugin
X-KDE-Library=myplugin          # = 模块名，必须与 myplugin.py 同名
X-Python-Version=3.13           # 可选
```

启用状态存在 `kritarc` 的 `[python]` 组，键名 `enable_<模块名>`，值为 `true/false`。首次安装默认**关闭**，需要在
`设置 → 配置 Krita → Python 插件管理器` 里勾选；随包插件由 `05-verify.ps1` 预置为启用（写入 `[python] enable_reveriepaint=true`），
这样用户装完就能看到面板。

---

## 3. 插件 API 的入口约定

`krita` 包的 `__init__.py` 会把几个名字塞进 `builtins`（源码 `plugin/krita/__init__.py`）：

```python
builtins.Application = Krita.instance()
builtins.Scripter    = Krita.instance()
builtins.Krita       = Krita.instance()
builtins.i18n / i18nc / qDebug
```

所以插件里不需要 `from krita import Krita` 也能直接用 `Application`。Krita 自带插件的两种典型写法：

```python
# 挂一个停靠面板（Docker）
from krita import DockWidgetFactory, DockWidgetFactoryBase
from .docker import MyDocker
Application.addDockWidgetFactory(
    DockWidgetFactory("my_docker",
                      DockWidgetFactoryBase.DockPosition.DockRight,
                      MyDocker))

# 注册一个扩展（动作/菜单/启动钩子）
from .ext import MyExtension
Scripter.addExtension(MyExtension(Application))
```

`DockWidget` 子类必须实现 `canvasChanged(self, canvas)`；面板生命周期由 Krita 的 `KisMainWindow` 管理——这正是
Android 版（无 QWidget）无法承载的部分。

---

## 4. 我们随包带的东西

| 内容 | 位置 | 作用 |
|---|---|---|
| `reveriepaint` 插件 | `share\krita\pykrita\reveriepaint\` + `.desktop` | 首次启动导入 ReveriePaint 的 291 个笔刷预设/118 个图案/255 个笔尖；提供「ReveriePaint」停靠面板（导入、诊断、打开插件目录） |
| `reverie_verify` 探针 | `share\krita\pykrita\reverie_verify\` + `.desktop` | 被加载时往 `%APPDATA%\krita\reverie-pykrita-probe.txt` 写一行标记；`05-verify.ps1` 靠它做自动化判定 |
| 笔刷源文件 | `share\reveriepaint\assets\{paintoppresets,brushes,patterns}` | 插件导入的源目录，不直接污染安装目录的 `share\krita` |

**为什么不把资产直接预装进 `share\krita\brushes`：** Krita 的笔刷预设按用户资源目录索引，直接塞进安装目录会在升级/卸载时丢失，
而且 `.kpp` 与笔尖是文件名引用的强耦合；导入到 `%APPDATA%\krita` 才能被用户正常管理（增删、打包、分享）。

---

## 5. 排错表

| 现象 | 根因 | 处置 |
|---|---|---|
| 配置日志里没有 `Found PyQt6` | 预编译依赖对不上 Python 版本 | 确认 `python.exe` 是 3.13 且在 `PATH` 首位；重新跑 `01-bootstrap-deps.ps1`；必要时 `-DPython_ROOT_DIR` |
| 构建里没有 `kritapykrita` 目标 | 三个变量有一个为假 | 同上；先看 `_build\CMakeCache.txt` 里 `HAVE_PYQT6` / `HAVE_SIP` / `HAVE_PYTHONLIBS` |
| 启动直接没有 Python 插件管理器入口 | `kritapykrita.dll` 没进发行目录或没被插件注册表扫到 | 检查 `lib\krita\kritapykrita.dll`；看 `帮助 → 显示 Krita 日志` 里 `Loaded Python Plugins` 段 |
| `ImportError: No module named 'krita'` | `lib\krita-python-libs` 缺失，或应用根目录判定错误 | 确认启动的是发行目录里的 `bin\krita.exe`，不是随意拷贝的 exe |
| `ModuleNotFoundError: PyQt6` | `lib\site-packages` 没合并进包 | 用官方 `package-complete.py` 产包，不要手工 `robocopy` 安装目录 |
| `DLL load failed: python313.dll` | 嵌入式 Python 没进 `python\`，或位数不对 | 重新打包；确认 `python313.zip` 与 `python313.dll` 都在 |
| 插件列表里看不到我们的插件 | `.desktop` 的 `ServiceTypes` 或 `X-KDE-Library` 写错 | 对照 §2 的格式；模块名必须与目录/文件名一致 |
| 勾选后启动报插件加载失败 | 插件顶层 `import` 抛异常 | 看日志末尾 traceback；PyKrita 会弹异常对话框（`excepthook`） |
| 改了 `.py` 不生效 | 插件已被导入到 `sys.modules` | 在插件管理器里取消勾选→确定→再勾选（会 `unloadModule` 后重新 import），或重启 |

---

## 6. 为什么内部标识仍叫 `krita`

发行名与图标改成 ReveriePaint，但**不要**改 `KAboutData` 的应用名：

- `KoResourcePaths` 的 `%APPDATA%\<appname>` 资源根目录跟着应用名走，改了会与用户已装的 Krita 彻底分家，笔刷/图案/工作区全部"消失"；
- PyKrita 的 `python/`、`lib/krita-python-libs`、`site-packages` 查找虽然基于"应用根目录"，但 `kritarc` 的 `[python]` 组、
  `%APPDATA%\krita\pykrita` 用户插件目录都带 app 名；
- `krita` 这个 Python 模块名本身也是编译期固定的（SIP 模块名 `PyKrita`/`krita`）。

改名属于"另起一个应用"，需要同步改资源路径、配置迁移、Python 模块名，收益是品牌一致性，成本是用户在两个程序之间的资产无法共享。
M1 的做法：**内部全保持 `krita`，只在窗口标题、关于页文案、快捷方式与安装包上体现 ReveriePaint**。
