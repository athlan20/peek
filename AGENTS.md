# 项目协作约定

Peek 是一个 macOS 菜单栏应用，用 Swift / SwiftUI（`MenuBarExtra`）开发，看系统状态、清理磁盘、卸载 App。全部用 Swift 原生实现，不依赖任何外部命令行工具。本文件指导参与开发的 AI Agent，只约定工作方式。

## 产品原则

- **界面极简。** 弹出面板只留必要信息：一个强调色、细分隔线、少量控件。不要往面板里加会让它变杂的功能。
- v1 需求见 `docs/v1-requirements.md`。
- **原创实现。** 功能、路径、规则只取公开事实，不照搬其他项目的源码。先把行为写成规格放进 `docs/`，再按规格实现。
- 已定：不开沙盒；不走 Developer ID 公证，用固定的自签名证书签名后直接分发；完全磁盘访问可选，没授权时功能降级；v1 不需要管理员权限；工程用 XcodeGen 从 `project.yml` 生成，`.xcodeproj` 不进版本库；最低 macOS 14；界面支持英文和简体中文，文案放 `Localizable.xcstrings`；Bundle ID 正式版 `cc.yuntianyou.peek`、开发版 `cc.yuntianyou.peek.dev`，发布后不能改。
- 其他还没定的设计，遇到时先问，不要自己决定。

## 开发与测试流程

一个需求或缺陷对应一个分支和一个 worktree。`test` 只用来集成测试，不往 `develop` 合，测试通过的是需求分支本身。完整说明见 `docs/dev-test-workflow.md`，包括固定冲突文件的解法。

- 目录：`peek/` 下每个子目录是一个 worktree，目录名就是 worktree 名。`master/` 是发布线和仓库主目录，`develop/` 是集成线，两处都不直接开发。
- 开工：`tools/req-start.sh PEEK-12 短标题`，在 `../PEEK-12` 开发。
- 提测：`tools/req-to-test.sh PEEK-12`，然后在 `peek/test/` 构建运行测试。缺陷回需求分支修，再提测一次。
- 测试通过：`tools/req-finish.sh PEEK-12`，合进 `develop` 并清理。纯文档、脚本类改动可加 `--force`。
- 脚本遇到冲突就停，解决并提交后重跑。脚本不推送，也不改工作项状态。`develop` 合 `master` 由人决定。
- 提交信息以需求号开头，如 `PEEK-12 feat: 说明`。
- 不同 worktree 共用同一份用户数据：改数据格式要兼容旧数据。会真正删除文件的功能，测试前先只看预览，或在临时目录里造测试数据。
- 不要用 `pkill`、`kill` 按进程名关进程，以免误关别的目录的 Peek 或 Xcode。
- 只修改当前任务需要的文件。开发需求时可以提交到需求分支；推送和其他提交要任务明确要求。
