# 卸载规则规格

PEEK-8 的唯一依据。卸载会删用户的 App 和数据，先写规则再写代码。残留的位置是 macOS 上的公开路径约定，匹配规则是 Peek 自己的设计，**不要照搬其他项目的源码**。安全判定直接复用清理的 `CleanGuard`（见 `docs/clean-rules.md` 的 G1–G6、G10），不另写一份。

## 1. 哪些 App 能卸载

列出的位置：`/Applications`（含一层子文件夹，如 `/Applications/Utilities`）、`~/Applications`。不扫 `/System/Applications`。

**不能卸载**（列表里显示但置灰，附原因）：

| 条件 | 原因 |
|---|---|
| 路径在 `/System` 下 | 系统自带 |
| Bundle ID 是 Peek 自己（`cc.yuntianyou.peek`、`.dev`） | 不能卸载自己 |
| `com.apple.*`，且不在下面“可卸载的 Apple App”里 | 系统自带 |
| 属于安全或管理类软件（`com.jamf`、`com.crowdstrike`、`com.sentinelone`、`com.paloaltonetworks`、`com.cisco.anyconnect`、`com.cisco.secureclient`、`com.eset`、`com.microsoft.wdav`） | 要用厂商自己的卸载程序 |
| App 正在运行 | 先退出（退出后刷新即可卸载） |

可卸载的 Apple App：`com.apple.dt.*`（Xcode 等）、`com.apple.FinalCut*`、`com.apple.Motion`、`com.apple.Compressor`、`com.apple.logic*`、`com.apple.garageband*`、`com.apple.iMovie`、`com.apple.iWork.*`、`com.apple.MainStage*`、`com.apple.Playgrounds`（且路径不在 `/System` 下）。

## 2. 列表显示

图标、名称、大小（`.app` 的实际占用，后台逐个量，量完才显示）、最后使用时间（Spotlight 的 `kMDItemLastUsedDate`，没有显示“—”）、来源标记（有 `Contents/_MASReceipt` 的是 App Store 安装）。可搜索（名称、Bundle ID），可按名称、大小、最后使用排序。

## 3. 残留的查找

输入：App 的 Bundle ID（记 B）、显示名称（记 N，取 `CFBundleDisplayName`，没有用 `CFBundleName`，再没有用 `.app` 文件名去掉后缀）。

只在 `~/Library` 下找，不碰 `/Library`（需要管理员权限，v1 不做）。**按 B 精确匹配的位置**：

| 位置 | 匹配 | 类别 |
|---|---|---|
| `Preferences` | `B.plist`、`B.*.plist` | 设置 |
| `Preferences/ByHost` | `B.*.plist` | 设置 |
| `Caches` | `B` | 缓存 |
| `Logs` | `B` | 缓存 |
| `HTTPStorages` | `B`、`B.binarycookies` | 缓存 |
| `WebKit` | `B` | 缓存 |
| `Cookies` | `B.binarycookies` | 缓存 |
| `Saved Application State` | `B.savedState` | 缓存 |
| `LaunchAgents` | `B.plist`、`B.*.plist` | 启动项 |
| `Application Scripts` | `B` | 设置 |
| `Application Support` | `B` | **个人数据** |
| `Containers` | `B` | **个人数据**（需要完全磁盘访问才能读，读不了标“无权限”） |
| `Group Containers` | 名字是 `group.B`，或 `<10 位大写字母数字的团队 ID>.B` | **个人数据** |

**按名称 N 匹配的位置**（只有这三处，且要求全部满足）：`Application Support/N`、`Caches/N`、`Logs/N`：

- 目录名与 N **完全相同**（不分大小写），不用包含、前缀匹配。
- N 至少 4 个字符，且不是通用词（`Code`、`Data`、`Cache`、`Helper`、`Support`、`Library`、`Updater`、`Update`、`Crash`、`Logs` 不匹配）。
- 系统里没有**另一个**已安装 App 的名称也是 N。
- 按 N 找到的一律归**个人数据**（Application Support）或缓存（Caches、Logs），并在预览里标出“按名称匹配”。

**同族保护**：候选的名字如果等于**另一个已安装 App** 的 Bundle ID，或另一个已安装 App 的 Bundle ID 是候选名的点分前缀（例如卸载 `com.foo.App` 时遇到属于 `com.foo.App.Pro` 的目录），整条跳过。

**不碰**：`Documents`、`Desktop`、`Downloads` 里的任何文件；用户自己创建的文档；`Keychains`（凭据在系统里，不处理）；与厂商共用的目录（如 `~/Library/Application Support/Adobe`、`Microsoft`，因为只按 B 和 N 精确匹配，不会命中）。

## 4. 预览与勾选

- 第一项永远是 App 本体，默认勾选，不能取消（取消就没有卸载了）。
- 类别默认勾选：设置、缓存、启动项**勾选**；**个人数据不勾选**，每条旁边标明“可能含有你的数据”。
- 每一项显示路径和大小，可展开看明细，能单项取消。
- 找不到任何残留时，只显示 App 本体和“没有找到残留文件”。

## 5. 执行

1. 每一项执行前重新做安全检查：`CleanGuard.check`（G1、G2、G3、G6、G10），确认路径仍在原位、类型和（设备号, inode）没变；再确认 App 没在运行。有变化就跳过该项并说明。
2. **一律移到废纸篓**（`FileManager.trashItem`），不直接删除。
3. App 本体先处理。`trashItem` 失败时（macOS 13 起的“App 管理”权限、或 App Store 安装的 App 需要管理员密码），**回退到交给 Finder**：`tell application "Finder" to delete POSIX file "<路径>"`，需要“自动化”授权，系统会弹窗。Finder 也失败就报告“无法移除 App 本体”，**不继续删它的残留**（避免留下一个没数据的空壳 App）。
4. 残留逐项移到废纸篓，单项失败不影响其他项，计入失败数。
5. 全部结束后写历史：`HistoryEntry(kind: .uninstall, itemCount:, freedBytes:, failedCount:, note: <App 名称>)`，释放字节为成功移走的项在扫描时的占用之和。

## 6. 测试

路径可注入（`~/Library` 根、应用目录、已安装 App 列表、运行中 App 列表），单元测试用临时目录造数据：按 B 精确匹配、按 N 的各项限制、同族保护、个人数据默认不勾选、保护路径被拒、执行前文件被换掉（G11）、App 在运行时拒绝。**真机测试只用你自己造的测试 App，不要拿正在用的 App 试。**
