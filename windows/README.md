# ReveriePaint · Windows 移植工程

把 ReveriePaint 搬到 Windows，并把 Krita 原生的 Python 插件系统（PyKrita）接回来。

> 当前状态：**M1 源码级移植完成，需要在 Windows 机器上编译验证**。
> 本文档所描述的工具链、配置项、插件加载协议均已对照 Krita 6.0.4 源码与官方 Windows 构建文档核对；
> 编译产物尚未在真实 Windows 环境跑过，见每节末尾的「验证清单」。

---

## 一、先看结论

Windows 版不是"把 App 打个桌面壳"，而是换了一层外壳、留下同一套内核：

| 层 | Android 版（本仓库） | Windows 版（本工程） |
|---|---|---|
| 外壳 | Jetpack Compose 触控界面（471 个 Kotlin 文件 / 约 20 万行） | Krita 6 桌面外壳（`KisMainWindow` + `KisPart`，菜单/停靠面板/快捷键齐全） |
| 内核 | Krita 库 + `ReverieCore`（C++，JNI 桥接） | 同一批 Krita 补丁与笔刷数据，直接打在 Krita 6 桌面构建上 |
| 输入 | `MotionEvent` + 自绘 `View`（`CanvasTouchView.kt` 9520 行） | Krita 原生画布：数位板 WinTab / Windows Ink、鼠标、快捷键 |
| Python | 无（引擎只链 Krita core，Qt Widgets 插件系统根本没有编进去） | 原生 PyKrita：插件管理器 + Docker 面板 + 动作 + 脚本 + 批处理 |

为什么必须这样选（三条硬约束，详见 `docs/PORT-PLAN.md`）：

1. **PyKrita 的插件不是"脚本"，是 Qt 界面插件。** 插件通过 `Application.addDockWidgetFactory(...)` 往 `KisMainWindow` 上挂 `QDockWidget`，通过 `Scripter.addExtension(...)` 注册扩展。没有 Qt 主窗口就没有宿主，Compose 界面里无处安放。
2. **Krita 本身在 Windows 上是一等公民。** 官方 Windows 构建走 llvm-mingw clang 21 + 预编译依赖，`plugins/python` 与 `plugins/extensions/pykrita` 只要探测到 Python/PyQt6/SIP 就会编进去，不需要"移植 Python"。
3. **Compose 界面无法在本次交付里整体搬过去。** `CanvasTouchView` 的 248 处 `MotionEvent`、自绘 `android.graphics.Canvas`、288 个引用 `android.*` 的文件，属于"重写画布层"级别的工程量，按 M2 分阶段做（`docs/PORT-PLAN.md` 有拆解清单）。

ReveriePaint 在移动端真正独有的东西——剪切蒙版、圆头笔刷边缘修复、换页历史崩溃修复、261 支笔刷/图案预设——都保留在 Windows 版里。

---

## 二、环境要求

| 项 | 要求 | 说明 |
|---|---|---|
| 系统 | Windows 10/11 x64 | 仅 x64 |
| 磁盘 | ≥ 120 GB 空闲 | 依赖包 + 构建目录很大 |
| 内存 | ≥ 16 GB | `ninja` 并行度按内存调 |
| Git | 任意较新版本 | |
| CMake | **3.31.x** | 4.x 上游明确不支持 |
| Ninja | 任意较新版本 | 单文件，建议与 `cmake.exe` 同目录 |
| 编译器 | **llvm-mingw 20251118 (UCRT, clang 21)** | 官方工具链。不要用 MSVC：上游明确说 MSVC 构建存在 codegen 性能问题 |
| Python | **3.13 x64**（在 PATH 里） | Krita 6 分支要求；3.10 是 5.2 分支的旧口径 |
| 可选 | Inno Setup 6 | 只做安装包时需要 |

工具链路径不要带空格；`PATH` 里不要混入其它编译器或 Python 环境。

下载地址：llvm-mingw → `https://github.com/mstorsjo/llvm-mingw/releases`（`llvm-mingw-20251118-ucrt-x86_64.zip`）；CMake → `https://cmake.org/download/`；Ninja → `https://github.com/ninja-build/ninja/releases`。

---

## 三、六步跑通

所有脚本在 PowerShell 里执行，参数都有默认值，按需覆盖。

```powershell
cd windows\scripts

# 0. 体检：逐项检查工具链、磁盘、Python 版本
.\00-check-prereqs.ps1 -LlvmMingw "C:\deps\llvm-mingw-20251118-ucrt-x86_64" -NinjaDir "C:\deps\Ninja"

# 1. 拉源码 + 拉预编译依赖 + 生成 env.bat（首次约 20~60 分钟，看网速）
.\01-bootstrap-deps.ps1 -Root "C:\krita-dev" -LlvmMingw "C:\deps\llvm-mingw-20251118-ucrt-x86_64" -NinjaDir "C:\deps\Ninja"

# 2. 打 ReveriePaint 补丁（逐条判定，Android 专用补丁自动跳过）
.\02-apply-patches.ps1 -Root "C:\krita-dev"

# 3. 编译 + 安装到 _install（首次 40~120 分钟）
.\03-build.ps1 -Root "C:\krita-dev"

# 4. 组装便携版 dist\ReveriePaint（含 Python 运行时、PyKrita、内置笔刷）
.\04-stage-portable.ps1 -Root "C:\krita-dev"

# 5. 校验：PyKrita 是否真的加载起来了（会启动一次程序，写探针文件后退出）
.\05-verify.ps1 -Root "C:\krita-dev"
```

跑完后：

```powershell
.\run-reveriepaint.bat
```

或者直接双击 `dist\ReveriePaint\ReveriePaint.exe`（M1 里它就是 `bin\krita.exe` 的启动包装，见 `docs/PORT-PLAN.md` §4）。

---

## 四、目录说明

```
windows/
├── README.md                       ← 你在读这个
├── docs/
│   ├── PORT-PLAN.md                移植方案、Android→Windows 差异表、M2/M3 拆解
│   ├── PYKRITA-RESTORE.md          Python 插件系统恢复的机制、目录、协议、排错
│   ├── PATCH-MANIFEST.md           17 条 Krita 补丁逐条取舍与验证结果
│   └── BUILD-NOTES.md              构建踩坑记录（依赖版本、常见报错）
├── scripts/
│   ├── 00-check-prereqs.ps1        环境体检
│   ├── 01-bootstrap-deps.ps1       源码 + 依赖 + env.bat
│   ├── 02-apply-patches.ps1        补丁应用与跳过判定
│   ├── 03-build.ps1                cmake + ninja install
│   ├── 04-stage-portable.ps1       组装便携发行目录
│   ├── 05-verify.ps1               PyKrita 加载探针 + 产物完整性检查
│   ├── build-all.ps1               一键串起 00~04 + Inno Setup
│   ├── run-reveriepaint.bat        开发期启动
│   └── lib/common.ps1              公共函数（日志、路径校验、调用 cmd）
├── ci/windows-build.yml            GitHub Actions：windows-latest 上编译并出安装包
├── pykrita/                        随包 Python 插件（靠 PyKrita 工作，等于自带回归测试）
│   ├── kritapykrita_reveriepaint.desktop
│   ├── reveriepaint/__init__.py    插件入口：注册 Docker + 动作
│   ├── reveriepaint/docker.py      「ReveriePaint」停靠面板
│   ├── reveriepaint/assets.py      内置笔刷/图案导入
│   ├── reveriepaint/diagnostics.py 环境诊断（Python/PyQt/krita 模块/插件目录）
│   └── kritapykrita_reverie_verify.desktop + reverie_verify/   加载探针
├── installer/reveriepaint.iss      Inno Setup 安装脚本
├── patches/                        补丁集：krita/ 下 17 条 + 0005b 重基补丁
└── tests/test_assets_import.py     资产导入逻辑的独立测试（不需要 Krita）

笔刷/图案资产不复制进本目录（约 54MB），打包时直接从仓库 app/src/main/assets 读取；
04-stage-portable.ps1 会自动定位，也可用 -AssetSource 指定。
```

---

## 五、这一版有什么 / 没有什么

**有：**

- Krita 6 桌面窗口、画布、图层、笔刷引擎、动画时间轴、滤镜、导出，Windows 原生数位板压感
- ReveriePaint 的 Krita 补丁：剪切蒙版（`0005`）、圆头笔刷边缘修复（`0004`）、换页/事务崩溃修复（`0011`/`0012`）、笔刷性能实验（`0013`–`0016`）、网格笔刷 HSV 修复（`0017`）
- ReveriePaint 的 268 个 `.kpp` 预设 + 7 个 `.myb`（共 275 个笔刷预设）、255 个笔尖、118 个图案，首次启动自动导入用户资源目录（可在面板里重跑）
- 完整 PyKrita：插件管理器、脚本编辑器（Scripter）、批量导出、十笔刷/十脚本、项目管理、以及随包自带的 `reveriepaint` 面板
- 便携版发行目录 + Inno Setup 安装脚本

**没有（M2/M3 范畴，见 `docs/PORT-PLAN.md`）：**

- 手机版那套触控界面（顶栏/画笔工坊/图层树/参考窗/回放手势）
- `ReverieCore` 里移动端特有的应用层能力（分格切分、中间帧、SRT 分镜、笔迹回放）——这些跑在自有文档模型上，桌面端要按 Krita 的 `KisDocument` 重新落
- 遥测（Windows 版默认完全不联网上报）

---

## 六、已经在 Linux 侧验证过的部分

移植工程里有相当一部分不是"文档承诺"，而是在本机跑过的：

| 项 | 验证方式 | 结果 |
|---|---|---|
| 补丁能否打到 Krita 6.0.4 | 浅克隆 `v6.0.4`（`e7e52a7`），逐条 `git apply --3way` | 桌面补丁 10 条 + 重基补丁 1 条全部成功；PSD 两个文件的冲突已重写为 `0005b` |
| 补丁脚本本身 | PowerShell 7.5 在真实源码树上跑完 `02-apply-patches.ps1` | 10 条依次应用并逐条提交，退出码 0 |
| PowerShell 语法 | `[Parser]::ParseFile` 逐个解析 7 个脚本 | 全部 OK |
| 插件 Python 语法 | `python -m py_compile` 5 个文件 | 全部 OK |
| 笔刷导入逻辑 | `python windows/tests/test_assets_import.py`，用真实 assets | 275 预设 / 255 笔尖 / 118 图案，二次运行正确跳过 |

没验证的是**只能发生在 Windows 上的部分**：C++ 编译链接、`kritapykrita.dll` 生成、PyKrita 真实加载、数位板输入。
这些正好对应下面的验证清单。

## 七、验证清单（编译后在 Windows 上逐条打勾）

- [ ] `03-build.ps1` 末尾出现 `PyKrita` 相关构建目标，`_install\share\krita\pykrita\` 下有 `krita` 包与 `*.desktop`
- [ ] `05-verify.ps1` 报告 `PYKRITA_OK`（探针插件被加载并写出标记文件）
- [ ] 启动后 `设置 → 配置 Krita → Python 插件管理器` 能看到 `reveriepaint` 与内置插件，勾选状态可保持
- [ ] 「ReveriePaint」面板能打开，诊断页显示 Python 3.13 + PyQt6 + `krita` 模块路径
- [ ] 面板里点「导入内置笔刷」后，笔刷预设数增加 275、笔尖 255、图案 118
- [ ] 数位板压感在画布上生效（`设置 → 配置 Krita → 数位板`）
- [ ] 打开/保存 `.kra`、导出 PNG 正常，剪切蒙版图层（clipping）可用

---

## 八、没有 Windows 机器时怎么出 exe

先说约束：Krita 的 Windows 依赖是 **Windows 二进制**（`moc.exe` / `windeployqt.exe` 等构建期工具要在 Windows 上跑），
交叉编译不可行；本移植工程的运行环境是 Linux 云主机（2 核 / 3GB 内存，无 mingw、无 wine、无 Inno Setup），
因此**在这里产不出 exe 或安装包**，只能把"编译 + 打包"做成可一键执行的流水线。

### 路径 A：自己的 Windows 机器（推荐，可控）

```powershell
cd windows\scripts
.\build-all.ps1 -Root "C:\krita-dev" `
    -LlvmMingw "C:\deps\llvm-mingw-20251118-ucrt-x86_64" -NinjaDir "C:\deps\Ninja"
```

串起 00→04，再调 `iscc` 出安装包。产物：

```
C:\krita-dev\dist\ReveriePaint\          便携目录
C:\krita-dev\dist\ReveriePaint.zip       便携压缩包
windows\out\ReveriePaint-*-setup.exe     安装包
```

预计：依赖下载 10~20 分钟 + 编译 40~120 分钟（8 核）；磁盘准备 120GB。
跑完务必再执行 `05-verify.ps1`，它会启动一次程序验证 PyKrita 真的加载。

### 路径 B：GitHub Actions（不需要本地 Windows）

1. 把 `windows/` 放到 ReveriePaint 仓库根（与 `app/` 同级）；
2. 把 `windows/ci/windows-build.yml` 复制到 `.github/workflows/windows-build.yml`；
3. push 后到 Actions 页面点 **Run workflow**（或推 `v*` 标签自动触发）。

工作流会自动：装 Python 3.13 / llvm-mingw 20251118 / Ninja / CMake 3.31 → 拉依赖 → 打补丁 → 编译 → 组包 → 文件级校验 → Inno Setup 出 exe → 上传 Artifacts。

产物在运行页的 **ReveriePaint-Windows** 附件里：`ReveriePaint.zip` 与 `ReveriePaint-*-setup.exe`。
4 核 runner 预计 2~4 小时，超时上限设的是 360 分钟。

### 路径 C：给我一台 Windows 环境

如果你能开通一台 Windows 云主机（或给可用的远程环境），我可以直接在里面跑 01→05，
按真实报错收敛（大概率会踩到 PyQt6 版本、路径空格、7-Zip 缺失这类问题），并把 exe 回传给你。

> 三条路径都依赖同一个前提：**依赖能正常下载**（KDE 的预编译包与 GitHub Release）。
> 如果目标机器在内网受限，需要先把 `krita-deps-management` 的下载源做镜像。
