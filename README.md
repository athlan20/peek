# Peek

macOS 菜单栏应用：看系统状态、清理磁盘、卸载 App。官网：https://peek.yuntianyou.cc

- v1 需求：`docs/v1-requirements.md`
- 开发和测试流程：`docs/dev-test-workflow.md`
- 签名：`docs/signing.md`

## 环境

- macOS 14 或更新
- Xcode（`xcode-select -p` 要指向 Xcode.app，不能是 CommandLineTools）
- XcodeGen：`brew install xcodegen`

## 构建

`Peek.xcodeproj` 由 `project.yml` 生成，不进版本库。

```bash
xcodegen generate      # 生成工程；改了 project.yml、切换分支、合并或新增文件后都要重跑
open Peek.xcodeproj    # 在 Xcode 里运行 Peek scheme
tools/verify.sh        # 命令行编译 Debug，提测和合入前脚本会自动跑
```

Debug 构建叫 "Peek Dev"，Bundle ID `cc.yuntianyou.peek.dev`，和正式版互不干扰。运行后只在菜单栏出现图标，Dock 里没有。

## 目录

| 目录 | 内容 |
|---|---|
| `Peek/App` | 程序入口、菜单栏 |
| `Peek/Panel` | 弹出面板 |
| `Peek/System` | 系统状态采集、健康分 |
| `Peek/Clean` | 清理 |
| `Peek/Analyze` | 磁盘分析 |
| `Peek/Uninstall` | 卸载 |
| `Peek/Optimize` | 系统维护 |
| `Peek/History` | 历史记录 |
| `Peek/Settings` | 设置窗口 |
| `Peek/Skins` | 皮肤接口和各皮肤 |
| `Peek/Resources` | 素材、文案（英文和简体中文） |
| `Config` | Debug / Release 的签名配置 |
| `tools` | 开发流程脚本、构建校验 |

每个目录里的 `README.md` 写了它对应哪个需求。
