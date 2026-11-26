# Windows 移植方案

> 结论：Windows 版以 **Krita 6 桌面体系**作外壳，保留 ReveriePaint 的**内核补丁与笔刷资产**，并把 **PyKrita 完整接回**。
> 手机版的 Compose 触控界面不在此次移植范围内，按 M2 分阶段推进。

---

## 1. 现状盘点（本仓库实测）

| 项 | 数值 | 来源 |
|---|---|---|
| Kotlin 源文件 | 471 个 / 201,199 行（`app/src/main`） | `find` + `wc -l` |
| ├ `core/`（引擎桥 + ViewModel） | 165 个 / 66,692 行，其中 97 个引用 `android.*` | 同上 |
| ├ `model/`（纯数据模型） | 116 个 / 20,296 行，仅 4 个引用 `android.*` | 同上 |
| └ `ui/`（Compose 界面） | 188 个 / 113,369 行，**185 个引用 `android.*`** | 同上 |
| C++ 引擎 | 52 个 `.cpp` + 30 个 `.h` | `find` |
| `MotionEvent` 引用 | 248 处（`CanvasTouchView.kt` 单文件 9,520 行） | `grep` |
| `AndroidBitmap_*` 调用 | 53 处，分布在 8 个 JNI 文件 | `grep` |
| Android 平台专有调用 | 28 处（`android/log.h`、`<jni.h>`、`jnigraphics`、`AAssetManager`、`dlopen`） | `grep` |
| Krita 补丁 | 17 条（`patches/krita/`） | — |
| 内置资产 | 268 个 `.kpp` + 7 个 `.myb`（275 个预设）、255 个笔尖、118 个图案 | `app/src/main/assets` |

架构铁律里有一条对移植影响最大：**「Qt 无 GUI 运行」——引擎惰性创建 `QCoreApplication`，禁止任何 QWidget 依赖**（`AGENTS.md` §4.7）。
这条在 Android 上是性能与体积的最优解，在 Windows 上正好是 PyKrita 的死穴：Python 插件要靠 `QApplication` + `KisMainWindow` 才能挂 Docker。

---

## 2. Android → Windows 能力对照

| 能力 | Android 版实现 | Windows 落地方式 | 工作量 |
|---|---|---|---|
| 窗口与页面路由 | `MainActivity` + `Page.HOME/CREATE/PAINTING/REPLAY` | `KisMainWindow` + `KisPart`（多文档、欢迎页、会话恢复） | 换壳 |
| 画布渲染 | 自绘 `View` + `android.graphics.Canvas` + 双缓冲 Bitmap | `KisCanvas2`（OpenGL 画布、瓦片合成、色彩管理） | 换壳 |
| 笔迹输入 | `MotionEvent` 手写解析（压感/倾斜/悬浮/双指手势） | WinTab / Windows Ink（`KisCanvas2` 原生支持）+ 快捷键 | 换壳 |
| 位图跨语言传输 | `AndroidBitmap_lockPixels`（jnigraphics） | 桌面 UI 直接读 Krita 投影，不需要 JNI 位图；M2 若保留 JNI 则改 `ByteBuffer` 零拷贝 | 仅 M2/M3 |
| 文件读写 | SAF / `DocumentFile` / MediaStore | `QFileDialog` + `KFileWidget`（Krita 已有） | 换壳 |
| 资源加载 | `AAssetManager` + `assets/` | Krita 资源目录（`brushes`/`paintoppresets`/`patterns`），走 `KoResourcePaths` | 一次性导入 |
| 配置存储 | `SharedPreferences` | `kritarc`（`KConfig`），插件启用状态在 `[python]` 组 | 换壳 |
| 崩溃处理 | `ReverieCrashHandler`（Android tombstone 风格） | Win32 `MiniDumpWriteDump` + Krita 自带崩溃对话框 | M3 |
| 线程模型 | `HandlerThread` + 专用渲染线程 | `QThread` / Krita 的 `KisRenderingLoop` + 笔画队列 | 换壳 |
| 国际化 | `strings.xml`（简中/英/日/繁/猫猫语） | Krita 的 `.po`（`ki18n`），保留简中与英文优先 | 后续 |
| Python 插件 | 不存在（未构建 `plugins/python`） | 原生 PyKrita（插件管理器 + Docker + Scripter + 批处理） | 打通构建与打包 |

---

## 3. 三条路线与取舍

### A. Krita 桌面外壳（本工程采用）

- 用 Krita 6 的 `KisMainWindow` / `KisPart` / `KisCanvas2` 作应用外壳，ReveriePaint 以 **补丁 + 资产 + 随包 Python 插件** 的形式并入。
- 优点：PyKrita 天然可用（Docker 有宿主）；Windows 数位板、快捷键、多文档、会话恢复全部白送；Krita 的 Windows 构建链成熟。
- 代价：手机版的触控界面与移动端专属应用层能力（分格切分、中间帧、SRT 分镜、笔迹回放）不在这一版里。

### B. Compose Desktop 整体迁移

- 把 188 个 `ui/` 文件迁到 Compose Multiplatform，`core/` 的平台依赖换成 expect/actual。
- 硬门槛：
  1. **输入**：Compose Desktop 的 `PointerEvent` 没有压感/倾斜，需 JNA 直调 `WM_POINTER` 或 `Wintab32.dll`；`CanvasTouchView` 的 248 处 `MotionEvent` 语义（历史点、批处理 flush、双指手势状态机）要整段重写。
  2. **渲染**：`android.graphics.Bitmap/Canvas/Paint` 需改 Skia `Image`/`Canvas`；双缓冲 + 瓦片 COW 状态机（`DisplayTileState.kt`）要按 Skia 后端重建。
  3. **文件与配置**：288 个文件引用 `android.*`，SAF → Win32 对话框、`SharedPreferences` → ini/json，属于全量改写。
- 估算：4~8 人周起步，且画布延迟/手感需要重新调优。

### C. 混合（Compose 主界面 + Qt 宿主窗口）

- 理论可行，实际体验割裂：Qt 只能把**外部原生窗口**嵌进 Qt（`QWindow::fromWinId`），反过来把 `QDockWidget` 嵌进 AWT/Skia 窗口没有受支持路径（`QWidget::createWindowContainer` 需要 QWindow 父级）。
- 结论：不作为交付形态。

**选择 A 的核心理由**：Python 插件是 Qt 界面插件，不是纯脚本；只要外壳不是 Qt 主窗口，"把原生 Python 插件加回来"就只能做成半成品。

---

## 4. M1 交付物与实现细节

### 4.1 构建链

```
llvm-mingw (clang 21, UCRT)  ─┐
Python 3.13 + PyQt6 + SIP    ├─→ CMake/Ninja ─→ krita.exe + libkritapykrita + plugins/python/*
预编译依赖 (krita-deps)      ─┘
```

依赖统一由 KDE 的 `krita-deps-management` 拉取（`setup-env.py --full-krita-env`），生成 `env.bat`，后续所有构建命令都在 `cmd /c "env.bat && ..."` 里执行——PowerShell 里直接调 `.bat` 不会保留环境变量，脚本已按此处理。

### 4.2 补丁策略

- 只打**桌面适用**的补丁，Android 专用补丁（平台胶水、MyPaint 静态注册、`libs/ui` Android 分支）跳过。
- 因为补丁原本基于 `reverie-android` 分支，与 `v6.0.4` 存在漂移，脚本用 `git apply --3way` 逐条尝试，失败不强行合入、只记录，避免把半截补丁带进构建。
- 逐条结论见 `PATCH-MANIFEST.md`。

### 4.3 资产导入

`app/src/main/assets` 的三个目录直接映射到 Krita 资源类型：

| 源目录 | Krita 资源目录 | 类型 |
|---|---|---|
| `paintoppresets/*.kpp` | `%APPDATA%\krita\paintoppresets` | 笔刷预设 |
| `brushes/*.gbr / *.gih / *.png / *.svg` | `%APPDATA%\krita\brushes` | 笔尖 |
| `patterns/*.pat / *.png` | `%APPDATA%\krita\patterns` | 填充图案 |

首次启动由随包插件 `reveriepaint` 自动导入（写一次性标记文件，避免每次启动重复拷贝），面板里也提供手动重跑按钮。
导入逻辑已在 Linux 上用真实资产跑通：275 / 255 / 118 个文件，二次运行全部跳过。`.kpp` 里引用的笔尖文件名与 `brushes` 目录一致，所以两个目录必须一起导入。

### 4.4 发行形态

- `dist\ReveriePaint\` 便携目录：`bin\krita.exe`、`share\krita\pykrita\`、`lib\krita-python-libs`、Python 运行时、Qt 与 KF6 依赖。
- 安装包：`installer\reveriepaint.iss`（Inno Setup 6），装到 `Program Files\ReveriePaint`，附带 `.kra` 文件关联。
- 品牌：沿用 Krita 内部标识（配置目录仍为 `krita`、资源路径不变），用户可见名称与图标改为 ReveriePaint。**不要**改内部 app name：`KoResourcePaths`、`%APPDATA%\krita`、Python 模块搜索路径都依赖它，改名的收益远小于坑（详见 `docs/PYKRITA-RESTORE.md` §2）。

---

## 5. M2：Compose 桌面外壳（后续）

按"先能看、再能画"的顺序推进，避免一次性重写 20 万行：

1. **平台抽象层**（新增 `platform/` 包，`expect/actual`）
   - 存储：`SettingsStore`（桌面用 ini/JSON）、`Paths`（`%APPDATA%\ReveriePaint`）
   - 对话框：`FileDialogs.open/save`（AWT `FileDialog` 或 JNA `IFileDialog`）
   - 剪贴板、通知、日志、字体、主题、屏幕密度
   - 位图：`NativeBitmap` 抽象（Android = `Bitmap`，桌面 = `ImageBitmap` + 直接 `ByteBuffer`）
2. **只读画布**：Compose `Canvas` + Skia `Image`，从引擎拉快照显示，先不做笔画提交。
3. **面板移植**：图层树/画笔面板只依赖 `model/`（4 个 Android 引用），是最好搬的一批。
4. **笔迹提交**：JNI 位图改 `ByteBuffer`；输入层用 JNA 调 `WM_POINTER`（Win10+）或 `Wintab32.dll`（旧驱动），先支持压感，再做倾斜与悬浮。
5. **移动端专属应用层能力**（分格切分、中间帧、SRT 分镜、笔迹回放）：这批逻辑在 `ReverieCore*.cpp` 里跑在自有文档模型上，需要改成围绕 `KisDocument` 的 Krita 插件/工具，工作量单独评估。

## 6. M3：ReverieCore 的 Windows 原生层

只有决定走"Compose 外壳"时才需要，清单如下（当前未实现，避免把无法编译验证的半成品塞进主干）：

| 文件 | Android 现状 | Windows 需要 |
|---|---|---|
| `reverie_jni_core.cpp` | `dlopen("libQt6Core_arm64-v8a.so")` + `QtAndroidPrivate::initJNI` | 删掉整段 JNI_OnLoad 逻辑；`System.loadLibrary` 即可，Qt 用 `QGuiApplication`（必要时 `-platform offscreen`） |
| `reverie_jni_common.h` | `AndroidBitmap_*` | 新增 `rp_bitmap` 抽象：桌面走 `GetDirectBufferAddress` |
| `reverie_jni_{animation,brush,core,io,layers,tools}.cpp` | 53 处 `AndroidBitmap_lockPixels` | 改成成对的 `rp_bitmap_lock/unlock`，保持早退分支也配对 |
| `ReverieCrashHandler.cpp` | Android tombstone | `MiniDumpWriteDump` + 符号路径 |
| `ReverieCoreIO.cpp` | `/sdcard` 等固定路径 | `QStandardPaths` |
| `CMakeLists.txt` | NDK + `libkrita*.so` | MSVC 不可用；用 llvm-mingw 链 `libkrita*.dll` 的导入库，版本必须与 M1 一致 |

---

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 补丁与上游漂移 | 补丁打不上 | `02-apply-patches.ps1` 逐条 `--3way`，失败即跳过并记录；关键特性（剪切蒙版）单独维护 rebase 分支 |
| Python/PyQt 版本错配 | PyKrita 不编译或运行期 `ImportError` | 固定 Python 3.13 + PyQt6 ≥ 6.7；`05-verify.ps1` 做导入探针 |
| 数位板驱动差异 | 压感失效 | WinTab 与 Windows Ink 两条路径都在 Krita 内；发行文档给出切换方法 |
| 与已装 Krita 抢配置 | 用户设置被改写 | 便携版用独立 `KRITA_USER_DIR`（启动脚本设置），安装版提示共存策略 |
| GPL 合规 | 分发风险 | 发行页必须附源码与补丁；ReveriePaint 图标/名称仅用于本项目分发 |

## 8. 回滚

M1 的所有改动都在 `C:\krita-dev` 之外的可重复步骤里：补丁可 `git reset --hard`，构建目录可整目录删除，随包插件是纯 Python 文件，删掉即回到原生 Krita。任何一步失败都不会破坏上游源码树。
