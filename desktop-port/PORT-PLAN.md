# ReveriePaint → Windows 桌面移植方案（v1.11.0 重做版）

## 0. 目标变更

| | 旧方案（已废弃） | 新方案 |
|---|---|---|
| 目标 | Krita 6 桌面外壳 + PyKrita 插件 | **原版 ReveriePaint 的界面、操作、功能**跑在 Windows 上 |
| 界面 | Krita 原生 | Compose 原版 UI |
| Python 插件 | 要求保留 | 不再考虑 |
| 引擎 | Krita 桌面库 | 同左（ReveriePaint 引擎本来就是 Krita 库 + JNI 包装） |

## 1. 上游版本

- 新版：**LanRhyme/ReveriePaint v1.11.0**（2026-11-26 发布，versionCode 71）
- 之前提供的源码是 1.9.0（versionCode 63），落后 8 个版本号
- 中间新增的大件：笔刷工坊重构、液态弹性动效、五点鱼眼透视、HSV/HSL 滤镜拆分、SRT 分镜独立画格、
  **多人茶绘 + 在线房间大厅（Beta，OkHttp + 房间码 + 入房审批 + 断线接管）**
- 规模：821 个 `.kt`（27.0 万行 Kotlin）、75 个 `.cpp/.h`（4.05 万行 C++）

## 2. 架构（同仓库加 desktop 目标，不改 Android 源码）

```
┌──────────────────────────────────────────────┐
│ ui        Compose 27 万行 → Compose Desktop  │
├──────────────────────────────────────────────┤
│ platform  967 处 android 引用 → expect/actual │
├──────────────────────────────────────────────┤
│ engine    4 万行 C++ → reverie_core.dll       │
│           （JNI 不变，桌面 JVM 照样支持）        │
├──────────────────────────────────────────────┤
│ Krita 6.0.4 libs（CI 已验证可在 Windows 编译） │
└──────────────────────────────────────────────┘
```

关键点：**引擎保留 JNI**。桌面 JVM 支持 JNI，Kotlin 侧 335 个 `external fun` 不用重写，
只需要把 `.so` 换成 `.dll`、把 `System.loadLibrary` 指到新库。

## 3. 引擎可移植性（实测）

| 平台耦合 | 涉及文件 | 处理方式 |
|---|---|---|
| `android/log.h` | 16 | shim 头，转到 stderr（`REVERIE_LOG=0` 可关） |
| `jni.h` | 13 | 用 JDK 自带 `jni.h`，无需改 |
| `android/bitmap.h` | 6 文件 / 57 处 | shim 头 + `com.reverie.paint.rt.RtBitmap` 类（字段 + DirectByteBuffer），调用点零改动 |
| `dlfcn.h` | 8 | 仅在 Android 上加载 Qt6Core.so 用，Windows 置空 |
| `sys/system_properties.h` | 4 | `__system_property_get` 恒返回「未设置」，只影响调试开关 |
| `unistd.h` | 4 | 强制包含 compat 头补 `sysconf` / `kill` |
| `sched.h` | 1 | 线程绑核空实现（Windows 亲和安全策略另做） |
| `sys/mman.h` | 1 | `mprotect` → `VirtualProtect` |
| `ucontext.h` / `unwind.h` | 1 | 崩溃回传，Windows 直接排除该文件 |
| `arm_neon.h` | 2 | **零工作量**：已有 `#if defined(__ARM_NEON)` 保护 + 标量兜底，x86 自动走通用路径 |

结论：引擎这半边是**天级工作量**，不是周级。已落地 `desktop-port/engine/`（shim 头 + CMake + 实现，本地已过语法校验）。

## 4. UI 层要替换的部分（967 处非 Compose 引用）

| API | 次数 | 桌面替代 |
|---|---|---|
| `Context` | 77 | 桌面 `AppContext`（资源/路径/Configuration） |
| `Bitmap` / `BitmapFactory` | 73 / 28 | Skia 光栅位图（`RtBitmap`） |
| `Build` | 46 | 固定机型档位（可配） |
| `Toast` | 35 | 自绘 Snackbar |
| `Log` | 28 | `println` 分级 |
| `Uri` / `Intent` / `FileProvider` | 25 / 23 / 8 | 桌面文件对话框 + 直接 `File` |
| `Handler` / `SystemClock` | 19 / 26 | 协程 / `nanoTime` |
| `MotionEvent` | 19 | Compose Desktop 指针事件（触控走 WM_POINTER 桥） |
| `Canvas` / `Paint` | 18 / 18 | Skia `Canvas`（`clipOutRect` 用 `ClipMode.DIFFERENCE`） |

桌面端必须砍掉（Android 独有，无对应物）：Glance 桌面小组件、系统分享、通知栏、
`androidx.input:input-motionprediction` 笔迹预测、`graphics-core` 的 Android 画质增强。

## 5. 阶段与验收

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| **M1 引擎** | 4 万行 C++ 编成 `reverie_core.dll` | DLL 产出 + 全部 JNI 符号导出（`dumpbin /exports` 数量对齐 335） |
| **M2 骨架** | platform 层 + Compose Desktop 启动 | 能开空窗口、加载语言包/资源、OOM 不崩 |
| **M3 画布** | 画布 + 笔刷 + 图层 + 手势 | 鼠标能画、滚轮缩放、右键取色；触控平板双指缩放/旋转/撤销 |
| **M4 收尾** | 漫画分格/中间帧/SRT/回放 + 打包 | exe 安装包，功能和原件对照清单逐项打勾 |

## 6. 风险（按严重度）

1. **Windows 触控与压感**：Compose Desktop 在 Windows 的多点触控支持弱，双指手势和笔压很可能要绕到 AWT/WM_POINTER 层自己接。这是全程最大不确定项。
2. **多人茶绘**：1.11.0 的在线房间依赖服务端与 OkHttp WebSocket；桌面能连，但房间协议对端兼容性需要实测。
3. **首轮编译循环长**：每次 CI 要重建 Krita（约 50 分钟）；M1 探针只 configure，单轮约 15 分钟。

## 7. 当前状态

- [x] 取回 v1.11.0 源码并落盘 `work/ReveriePaint-1.11.0`
- [x] 静态耦合审计（引擎 9 类 / UI 967 处）
- [x] 引擎 shim 层与 CMake 骨架（`desktop-port/engine/`）
- [x] 移植脚本（windows/）入库，CI 不再依赖 CDN 临时链接
- [ ] M1：CI 上跑通 `reverie_core.dll` 编译（进行中）
