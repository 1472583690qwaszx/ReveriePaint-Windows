# Windows 构建踩坑记录

只记**有依据**的坑：要么来自 Krita 官方 Windows 构建文档，要么是本次移植验证时遇到的问题。

## 1. 工具链

| 坑 | 现象 | 处置 |
|---|---|---|
| 用 MSVC | 能编，但运行性能明显差（上游明确说 MSVC codegen 有问题） | 只用 llvm-mingw clang 21（`llvm-mingw-20251118-ucrt-x86_64`） |
| CMake 4.x | 配置阶段直接报错 | 固定 3.31.x |
| PATH 里混了 MSYS2 / VS / 别的 Python | 配置时找到错的头文件/Python，或链接期符号错乱 | 新开一个干净的 cmd/PowerShell，先 `env.bat` 再构建；本工程的脚本用 `cmd /c` 独立进程执行，不继承你当前的编译环境 |
| llvm-mingw 路径带空格 | 构建脚本拼路径出错 | 装到 `C:\deps\...` 这类无空格路径 |
| 路径过长 | 依赖解包失败 | 工作目录用 `C:\krita-dev` 这种短前缀 |

## 2. Python / PyKrita

| 坑 | 现象 | 处置 |
|---|---|---|
| Python 版本不对 | `find_package(PyQt6)` 找不到，或链接 Python 失败 | Krita 6 分支要 **3.13 x64**；3.10 是 5.2 分支 |
| `PYTHONHOME` / `PYTHONPATH` 被设置 | CMake 探测到系统 Python 而不是依赖里的 | 清掉这两个环境变量（`00-check-prereqs.ps1` 会检查 PYTHONHOME） |
| 位宽不对 | `TestCompileLinkPythonLibs` 失败 | 必须 64 位 |
| 打包缺 `python\` 目录 | 启动后插件管理器空白，日志 `Bundled Python not found` | 用官方 `packaging/windows/package-complete.py` 产包，别手工 robocopy |
| `lib\site-packages` 缺 PyQt6 | 插件报 `ModuleNotFoundError: PyQt6` | 同上；检查 `_install\lib\site-packages\PyQt6` |

## 3. 补丁

| 坑 | 现象 | 处置 |
|---|---|---|
| 直接 `git apply` | 0004/0016/0014 等报 `patch does not apply` | 用 `--3way`，并且严格按 `02-apply-patches.ps1` 的顺序（0004 依赖 0002，0014 依赖 0013） |
| 打 Android 补丁 | `repository lacks the necessary blob` | 正常：fork 分支的 blob 不在上游仓库；桌面端本就不需要这些补丁 |
| 0005 的 PSD 两个文件打不上 | `psd_layer_section.cpp` / `psd_loader.cpp` 冲突 | 用本工程的重基补丁 `patches\0005b-psd-clipping-rebase.patch` |
| 补丁打到一半失败 | 树里留半条补丁，后续构建诡异崩溃 | 脚本每条成功后立即 commit，失败 `reset --hard` |

## 4. 打包

| 坑 | 现象 | 处置 |
|---|---|---|
| 没装 7-Zip | `package-complete.py` 直接 `7-Zip not found` 退出（exit 102） | 装 7-Zip，或设 `SEVENZIP_EXE` |
| `MINGW_BIN_DIR` 未设 | 脚本去找 `mingw32-make.exe`，llvm-mingw 里没有 | `04-stage-portable.ps1` 已把它指向 llvm-mingw 的 `bin` |
| 直接删 `python\python.exe` 之外的东西 | PyKrita 找不到 zip 里的标准库 | 官方脚本只删 `python.exe`/`pythonw.exe` 并清 pip/setuptools，照它做 |
| 杀软拦截 `.pyd`/`.dll` 写入 | 构建或启动失败且无明确报错 | 给工作目录加排除项 |

## 5. 运行

| 坑 | 现象 | 处置 |
|---|---|---|
| 与已装 Krita 共用 `%APPDATA%\krita` | 两边的工作区/笔刷互相影响 | 便携版想隔离就把 `APPDATA` 指到别处再启动（`set APPDATA=D:\RP\appdata`），代价是与已装 Krita 不共享资源 |
| 装了多个 Krita 版本 | `bin\krita.exe` 加载到别的版本的 Qt DLL | 只从发行目录启动；`PATH` 里不要有别的 Krita |
| 数位板无压感 | 画布只认鼠标 | `设置 → 配置 Krita → 数位板` 切 WinTab / Windows Ink；Wacom 驱动装最新 |

---

## 七、CI 实测踩到的两个坑（已在脚本里修掉）

### 1. 依赖分支选错 —— `ECM 5.101` vs `ECM 6.0`

现象：CMake 配置阶段直接失败。

```
CMake Error at CMakeLists.txt:468 (find_package):
  Could not find a configuration file for package "ECM" that is compatible
  with requested version "6.0".
    C:/krita-dev/_install/share/ECM/cmake/ECMConfig.cmake, version: 5.101.0
```

原因：`krita-deps-management` 的默认分支 `master` 是 **KF5** 依赖集（ECM 5.101、PyQt5、Qt5），Krita 6 走 Qt6 + KF6。
`setup-env.py` 的 `-b/--branch` 默认就是 `master`，所以即使 Krita 源码是 `v6.0.4`，拉下来的仍是 KF5 那套。

修法：`01-bootstrap-deps.ps1` 增加 `-DepsBranch`，同时用于克隆依赖仓库和传给 `setup-env.py`：

```powershell
.\01-bootstrap-deps.ps1 -Root C:\krita-dev -DepsBranch "transition.now/qt6"
```

对应依赖集：ECM 6.25、KF 6.25、PyQt6 6.11、SIP 6.15。

### 2. 编译器被 runner 的 GNU 抢走

现象：配置日志里出现

```
-- The CXX compiler identification is GNU 15.2.0
-- Check for working CXX compiler: C:/mingw64/bin/c++.exe
```

GitHub 的 `windows-latest` 镜像自带一套 `C:/mingw64` 的 GCC 且在 PATH 前面，`cmake` 默认探测到了它。
Krita 官方口径是 llvm-mingw（clang），用 GCC 编出来的东西和依赖里的 Qt/KF6 二进制 ABI 不一致。

修法：`03-build.ps1` 在配置时显式钉死编译器（读环境变量 `LLVM_MINGW`）：

```
-DCMAKE_C_COMPILER=<llvm-mingw>/bin/clang.exe
-DCMAKE_CXX_COMPILER=<llvm-mingw>/bin/clang++.exe
-DCMAKE_RC_COMPILER=<llvm-mingw>/bin/windres.exe
```

### 3. 顺带一提：`CMAKE_PREFIX_PATH` 的告警

配置日志里会出现

```
CMake Warning ... CMAKE_PREFIX_PATH variable is not set, we might NOT be able to detect SIP modules
```

这是 `cmake/modules/FindPythonLibrary.cmake` 在 `find_package(Python)` 阶段打的提前警告，此时依赖前缀还没进搜索路径。
只要后面 `find_package(ECM 6.0)` / `KF6` / `Qt6` 都能找到、并且 `kritapykrita` 目标确实生成，这条警告可以忽略。
