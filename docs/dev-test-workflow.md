# 开发 / 测试流程

一个需求或缺陷对应一个分支和一个 worktree。`test` 只用来集成测试，不往 `develop` 合。测试通过的是需求分支本身，由它合进 `develop`。

```text
develop ──start──▶ PEEK-12-短标题（worktree ../PEEK-12）
                        │ to-test                 │ finish（测试通过后）
                        ▼                         ▼
                   test（worktree ../test）       develop ──（发布时）──▶ master
```

| 目录 | 分支 | 用途 |
|---|---|---|
| `peek/master/` | `master` | 发布线，也是仓库主目录（`.git` 在这里）。不在这里开发 |
| `peek/develop/` | `develop` | 日常集成线，需求从这里拉出、合回这里。不在这里开发 |
| `peek/PEEK-12/` | `PEEK-12-短标题` | 开发和自测 |
| `peek/test/` | `test` | 集成测试，不改代码 |

这些目录都放在同一个 `peek/` 下，`peek/` 本身不是 git 仓库，目录名就是 worktree 名。每个目录都是一份完整的工程，用 Xcode 打开具体的需求目录。

## 四个步骤

| 步骤 | 做什么 | 命令 |
|---|---|---|
| 1. 开工 | 从 `develop` 拉分支，建同名 worktree，软链被忽略的文件 | `tools/req-start.sh PEEK-12 短标题` |
| 2. 开发 | 在 `../PEEK-12` 开发、自测、提交 | |
| 3. 提测 | 需求分支先同步 `develop`，再合进 `test`，然后在 `peek/test/` 构建运行测试 | `tools/req-to-test.sh PEEK-12` |
| 4a. 不通过 | 回需求分支改，再重复第 3 步 | |
| 4b. 通过 | 需求分支合进 `develop`，删 worktree 和分支 | `tools/req-finish.sh PEEK-12` |

脚本可以在任意 worktree 里运行，只做本地合并，不推送，也不改工作项状态。`develop` 合 `master` 是发布动作，由人决定。

## 约定

- **分支名**：`需求号-短标题`，需求号就是工作项编号（`PEEK-数字`）。短标题只用汉字、字母、数字、`-`、`_`，不超过 20 字。
- **提交信息**：以需求号开头，如 `PEEK-12 feat: 菜单栏显示磁盘占用`。
- **合并方式**：脚本一律用 `--no-ff`，合并提交写成 `PEEK-12-短标题：合入 test`，历史里能看出这批提交属于哪个需求。
- **冲突处理**：脚本遇到冲突就停下，退出码为 2。解决并 `git commit` 后重跑同一条命令。
- **自动校验**：提测和合入前，脚本会做一次构建校验：优先运行该目录下的 `tools/verify.sh`（工程确定构建命令后写，参数是目录路径），其次在有 `Package.swift` 时 `swift build`，都没有就跳过。仓库启用 git-lfs 时，还会检查 LFS 文件都已下载。校验不代替功能测试。
- **`test` 重置**：积累太乱时，用 `tools/req-to-test.sh --reset PEEK-12` 把 `test` 重置成 `develop`。脚本会列出重置前还在 `test` 里的需求，仍要测试的逐个重新提测。
- **跳过测试**：`req-finish.sh` 默认要求需求分支最新提交已在 `test` 里。纯文档、脚本类改动可加 `--force`。只合并、不清理加 `--keep`。
- **`develop` 又前进了**：`req-finish.sh` 会自动同步。没有冲突就直接合入，不用重测。有冲突时，手工解决的结果也算改动，要重新提测。
- **没有需求号的小改动**：用 `chore-<名称>` 分支（不带 `/`，目录名才能和分支名一致），手动 `git merge --no-ff` 进 `develop`。
- **`test` 这个名字**：工程里有 `test/` 目录时，`git log test` 会报歧义，要写 `refs/heads/test`。
- **依赖和工具链版本**：Xcode、Swift、XcodeGen、最低 macOS 版本统一，升级单独开一个需求做，不要夹在功能需求里。

## 固定冲突文件

以下是 Swift / Xcode 工程里常见的冲突点。工程用 XcodeGen 从 `project.yml` 生成，`.xcodeproj` 不进版本库；切换分支、合并或新增文件后，重新运行一次 `xcodegen` 再打开 Xcode。

| 文件 | 解法 |
|---|---|
| `project.yml` | 两边新增的 target、依赖、构建设置取并集；同一个设置两边改成不同的值，要找对方确认。合完运行 `xcodegen`，能编译再提交 |
| `Package.resolved` | 取 `develop` 的，再运行 `swift package resolve` 重新生成 |
| `Info.plist`、`*.entitlements` | 键取并集；同一个键两边改成不同的值，要找对方确认 |
| `*.xcassets`（图片、颜色集） | 图片不能合并，整文件二选一：`git checkout --ours <文件>` 或 `--theirs`，再 `git add`。同一个素材不要两个需求同时改 |
| 本地化文件（`*.strings`、`*.xcstrings`） | 条目取并集；同一个 key 两边不同，要找对方确认 |

## 共用资源

- **用户数据是共用的。** 所有 worktree 的 Peek 读写的是同一份偏好设置和数据（`~/Library/Preferences/`、`~/Library/Application Support/` 下按 Bundle ID 区分）。所有 worktree 的 Debug 构建都用 `cc.yuntianyou.peek.dev`，会互相覆盖偏好设置，也会抢同一个菜单栏位置；它和正式版 `cc.yuntianyou.peek` 分开，不影响本机装的正式版。测试时只运行一个开发版，改数据格式要带版本号并兼容旧数据。
- **清理会删真实文件。** 所有 worktree 的 Peek 清理的是同一台机器上的同一批文件。测会真正删除文件的功能前，先只看预览，或在临时目录里造测试数据，并在测试记录里写明。
- **运行文件是软链。** `CLAUDE.local.md` 等被忽略的文件指向 `peek/develop/`，不要单独维护。需要新增时，改 `tools/req-lib.sh` 的 `LINKED_PATHS`。
- **构建产物各目录各一份。** `DerivedData`、`.build/` 不进版本库，也不要软链到别的目录。
- **删目录前关掉 Xcode 里对应的窗口和运行中的 Peek。** 不要用 `pkill`、`kill` 按进程名清理，以免误关别的目录的进程。
- **`test/` 和 `develop/` 合入后要重新构建。** 已经开着的 Xcode 窗口或运行中的 Peek 用的还是旧代码。

## 工作项状态

工作项编号前缀是 `PEEK`。脚本不改状态，要等对应步骤成功后手动改，改完回查确认。

| 工作项类型 | 开工 | 提测 | 测试通过、合入 `develop` | 测试不通过 |
|---|---|---|---|---|
| 产品类需求 | 开发中 | 测试中 | 已完成 | 改回开发中，评论里写原因 |
| 业务类需求 | 开发中 | 保持开发中（这类工作流没有“测试中”） | 已完成 | 保持开发中，评论里写原因 |
| 技术类需求 | 处理中 | 保持处理中 | 已完成 | 保持处理中，评论里写原因 |
| 缺陷 | 处理中 | 已修复 | 已关闭 | 再次打开，评论里写原因 |

## 完成定义

1. 代码已提交，提交信息以需求号开头。
2. 校验已通过（脚本自动跑）。功能按改动范围在 `peek/test/` 里实际构建运行一遍。单元测试框架还没选定，选定后补到这里和 `tools/verify.sh` 里。
3. 相关文档已同步。
4. 工作项状态已更新，改完回查确认。脚本不会改状态，要等合并成功后再改。
5. 需要别人验收的，把验收要点写进工作项评论。

## 搭建目录

在新机器上，先装好 Xcode（`xcode-select -p` 要指向 Xcode.app）和 XcodeGen（`brew install xcodegen`），然后：

```bash
mkdir peek && cd peek
git clone <仓库地址> master
git -C master worktree add ../develop develop
```

`Peek.xcodeproj` 不进版本库：`req-start.sh` 建好 worktree 后会自动生成，`tools/verify.sh` 每次也会重新生成；手动切换分支或合并后，在该目录运行 `xcodegen generate`。正式版签名要导入团队证书，见 `docs/signing.md`。

第一次运行 `req-to-test.sh` 时，如果 `test` 或 `peek/test/` 不存在，脚本会自动建好。`master` 固定在 `peek/master/` 检出，`develop` 固定在 `peek/develop/`，`test` 固定在 `peek/test/`。
