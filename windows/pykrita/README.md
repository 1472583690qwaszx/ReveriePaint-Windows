# 随包 Python 插件

这两个插件是 ReveriePaint Windows 版的一部分，同时也充当 **PyKrita 是否正常的回归测试**。

```
pykrita/
├── kritapykrita_reveriepaint.desktop      # 描述文件：ServiceTypes=Krita/PythonPlugin
├── kritapykrita_reverie_verify.desktop
├── reveriepaint/                          # 插件模块（目录名 = X-KDE-Library）
│   ├── __init__.py                        # 注册停靠面板 + 后台导入资产
│   ├── docker.py                          # 「ReveriePaint」面板
│   ├── assets.py                          # 笔刷/笔尖/图案导入
│   └── diagnostics.py                     # 诊断报告
└── reverie_verify/
    └── __init__.py                        # 被加载即写探针文件
```

## 部署位置

安装目录（随包）：
```
<ReveriePaint>\share\krita\pykrita\
├── kritapykrita_reveriepaint.desktop
├── reveriepaint\
├── kritapykrita_reverie_verify.desktop
└── reverie_verify\
```
`04-stage-portable.ps1` 会把本目录整体拷进去。

用户目录（开发时更方便，改完重启 Krita 即生效）：
```
%APPDATA%\krita\pykrita\
```

## 启用

Krita 默认**不启用**第三方 Python 插件。两种方式：

1. `设置 → 配置 Krita → Python 插件管理器` 勾选 `ReveriePaint`；
2. 或直接改 `%APPDATA%\krita\kritarc`：
   ```ini
   [python]
   enable_reveriepaint=true
   enable_reverie_verify=true
   ```
   `05-verify.ps1` 走的就是第二种（等价于脚本化勾选）。

## 改了代码怎么生效

PyKrita 把插件 import 进 `sys.modules` 之后不会自动重载。改完 `.py`：

- 在插件管理器里取消勾选 → 确定 → 再勾选（会走 `unloadModule` + 重新 import），或
- 重启 Krita。

## 调试

- `帮助 → 显示 Krita 日志`：搜 `Loaded Python Plugins`、`Traceback`；
- 面板里的「诊断报告」会把 Python/PyQt/krita 模块路径、插件目录、资源计数写进
  `%APPDATA%\krita\reveriepaint-diagnostics.txt`；
- PyKrita 装了全局 `excepthook`，插件顶层抛异常会弹带 traceback 的对话框，不会静默失败。
