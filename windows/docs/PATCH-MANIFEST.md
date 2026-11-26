# Krita 补丁取舍清单（对 v6.0.4 实测）

验证方式：浅克隆 `KDE/krita` `v6.0.4`（commit `e7e52a7`），对 `patches/krita/` 下 17 条补丁逐条执行
`git apply --3way --whitespace=nowarn`，记录结果；失败项再单独定位冲突文件。验证日期 2026-11-17。

结论分三档：

- **默认打**：桌面版直接受益，且实测可应用
- **可选打**：移动端性能实验，桌面端收益不确定、影响面偏大
- **跳过**：Android 专用或纯文档

---

## 1. 默认打（9 条 + 1 条重基补丁）

| 编号 | 主题 | 涉及文件 | 实测 | 说明 |
|---|---|---|---|---|
| 0002 | 圆头笔刷 `KisMarkerPainter` 修复 | `libs/image/kis_marker_painter.cpp` | ✅ 直接应用 | 必须先于 0004 / 0016 |
| 0003 | 修复换页时 Swap `qFatal` | `kis_image_config.cpp`、`tiles3/swap/*` | ✅ 直接应用 | 大画布换页稳定性 |
| 0004 | 圆头笔刷边缘改 `COMPOSITE_OVER`，去掉裸 `memcpy` | `kis_marker_painter.cpp` | ✅ 依赖 0002，三方合并成功 | 消除笔画交叉白边 |
| 0005 | 剪切蒙版（clipping layer） | `kis_layer.*`、`kis_node.*`、`freehand_stroke.cpp`、`libkra/*`、PSD 相关 | ⚠️ 除 2 个 PSD 文件外全部干净应用 | 见下方 0005b |
| **0005b** | **本工程新增：PSD 剪切蒙版读写重基** | `libs/psd/psd_layer_section.cpp`、`plugins/impex/psd/psd_loader.cpp` | ✅ 在 0005 之后应用 | 把 0005 里因上下文漂移打不上的 2 个文件按 v6.0.4 重写：写出时 `nodeClipping` 取 `layerObj->clippingEnabled()`，读入时 `layerRecord->clipping == 1` 调 `enableClippingLayer(true)` |
| 0008 | `kis_lockless_stack.h` 适配 Qt 6.6 的 `QtGlobal` 变更 | `libs/global/kis_lockless_stack.h` | ✅ 直接应用 | 构建修复 |
| 0011 | Memento 管理器 `SIGABRT` 修复 | `libs/image/tiles3/kis_memento_manager.cc`（+ 一个文档 hunk） | ✅ 排除 `REVERIE-PATCHES.md` 后应用 | 换页历史崩溃 |
| 0012 | 事务中止路径修复 | `libs/image/kis_transaction_data.cpp` | ✅ 直接应用 | 撤销/重做稳定性 |
| 0015 | Sketch 笔刷 2D 查找表 O(N²)→O(1) | `plugins/paintops/sketch/kis_sketch_paintop.h` | ✅ 直接应用 | 纯性能，行为不变 |
| 0017 | 网格笔刷 HSV 变换修复 | `plugins/paintops/gridbrush/kis_grid_paintop.cpp` | ✅ 直接应用 | 颜色正确性 |

## 2. 可选打（3 条，默认不打）

| 编号 | 主题 | 涉及文件 | 实测 | 为什么不默认 |
|---|---|---|---|---|
| 0013 | `fillPainterPath` 块合并 + 实验笔刷 60fps 节流 | `kis_painter.cc/.h/_p.h`、`kis_experiment_paintop.cpp` | ✅ 可应用 | 改写 `KisPainter::fillPainterPath` 的填充路径，并引入 12ms/16px 的刷新节流。这套节奏是为手机小屏与低算力调的；桌面端有 OpenGL 画布与更快的 CPU，节流反而可能让笔迹变"钝"。另外它影响所有走 `fillPainterPath` 的功能（渐变填充、选区填充等），回归面大 |
| 0014 | 三角划分 25fps 拆分 | `krita_utils.cpp`、`kis_experiment_paintop.cpp` | ✅ 依赖 0013 | 与 0013 同一套实验，配套使用 |
| 0016 | Marker 笔刷缓存 | `kis_marker_painter.cpp` | ✅ 依赖 0002/0004 | 移动端热点优化，桌面端收益有限，但改动集中在单文件，想试可以单独打开 |

打开方式：`02-apply-patches.ps1 -IncludeExperimental`。

## 3. 跳过（5 条）

| 编号 | 主题 | 原因 |
|---|---|---|
| 0001 | Android 14 平台胶水（`KisAndroidUtils`、`KisAndroidExitInfo`、`KisAndroidScaling`、长按事件过滤器等） | 纯 Android；部分 hunk 依赖 fork 分支的 `KoColorSpaceRegistry.cpp` 内容，三方合并因缺 blob 失败。桌面端不需要 |
| 0006 | MyPaint 引擎 Android 静态注册 | Android 上无法用插件机制动态加载，才把 MyPaint 静态注册进 lib。桌面端走正常的插件加载，静态注册反而会重复注册 |
| 0007 | MyPaint SensorPack 的 `dlopen` 修复 | 依赖 0006 引入的 `register_static.cpp`，桌面端不存在该文件 |
| 0009 | `libs/ui/CMakeLists.txt` 的 Android 分支（视频/权限） | Android 构建专用 |
| 0010 | `docs/REVERIE-PATCHES.md` | 纯文档 |

---

## 4. 应用顺序（脚本里已固定）

```
0002 → 0003 → 0004 → 0005 → 0005b → 0008 → 0011 → 0012 → 0015 → 0017
[可选] 0013 → 0014 → 0016
```

顺序不是随意的：0004 / 0016 的上下文建立在 0002 之上；0014 建立在 0013 之上；0005b 建立在 0005 之上。
脚本对每条补丁 `git apply --3way`，成功后立即 `git commit`，失败则 `git reset --hard` 回滚到上一条，
所以中途失败不会留下"半条补丁"。

## 5. 已知风险

1. **`--3way` 依赖 patch 里的 pre-image blob。** 打 Android 补丁时会报
   `repository lacks the necessary blob to perform 3-way merge`——这不是冲突，是 fork 分支的 blob 不在上游仓库里。
   桌面补丁不受影响（实测全部成功），但升级到 Krita 6.1/6.2 后需要重新验证一遍。
2. **0005 的 `freehand_stroke.cpp` 改动**会给剪切蒙版的基准图层补 `setDirty`。若上游后续重写了笔画脏区计算，这条最容易冲突。
3. **0013/0014 属于实验性改动**，且没有自动化测试覆盖；任何"笔迹糊、渐变边缘异常"的问题先关掉这两条再排查。
4. 补丁只保证**能应用**，不等于**编译通过**——`kis_layer.h` 等接口在 6.0.4 中确认存在
   （`clippingEnabled()` / `enableClippingLayer()` / `findClippingBase()` 均已 grep 到），但真正的编译验证在 Windows 上完成。
