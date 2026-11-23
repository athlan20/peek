# 清理规则规格

这是开发清理功能（PEEK-5）的**唯一依据**。清理会删用户的真实文件，所以先写规则、评审，再写代码。实现时按本文档的规则写，**不要照搬其他项目的源码**；本文档里的路径是 macOS 上的公开事实，规则和结构是 Peek 自己的设计。

文档里的数字（天数、分钟数）是首版取值，实机试用后可以调，调整时只改这里，再改代码常量。

## 1. 约定

### 删除方式

| 记号 | 含义 |
|---|---|
| **直接删** | `FileManager.removeItem`。只用在能自动重新生成的内容上 |
| **废纸篓** | `FileManager.trashItem`。用户能从废纸篓恢复 |
| **工具命令** | 调用对应工具自己的清理命令（该工具存在时），不存在时按"直接删"处理或跳过，每条规则里写明 |
| **Finder 清空** | 通过 Finder 的 AppleScript 清空废纸篓，需要"自动化"授权 |

不用 `rm`、`find -delete` 这类 shell 命令删文件。工具命令只调用系统自带或用户已装工具的绝对路径，设超时，捕获退出码。

### 一条规则要写明的字段

分类、路径或匹配方式、保留条件、跳过条件、删除方式、是否需要完全磁盘访问（FDA）、默认是否勾选、**删了会不会丢用户数据**。

### 规则 id

`R1`–`R9` 是自动可用的分类，`F1`、`F2` 是授予完全磁盘访问后才增加的分类。扫描结果里每条记录都带规则 id，历史记录和"无权限"明细按它归类。

## 2. 全局安全规则

下面的规则对**所有分类**生效，优先于分类规则。任何一条无法确认，就跳过这一项，不删。

**G1 路径校验。** 路径必须是绝对路径；不含 `..` 这一段；不含控制字符；先把重复斜杠、末尾斜杠规范化，再做后面所有比对。

**G2 只删叶子，不删容器。** 规则只能命中具体的缓存目录、文件，不能命中它们的祖先。下面这些路径本身及其祖先**永远不删**，即使某条规则的通配符能匹配到它们：

- 系统：`/`、`/System`、`/usr`、`/bin`、`/sbin`、`/etc`、`/var`、`/private`、`/Library`、`/Applications`、`/Users`
- 用户主目录根，以及 `~/Library`、`~/Library/Application Support`、`~/Library/Caches`、`~/Library/Containers`、`~/Library/Group Containers`、`~/Library/Preferences` 这些容器目录本身
- 用户内容：`~/Documents`、`~/Desktop`、`~/Downloads`（目录本身；里面的安装包按 R8 处理）、`~/Pictures`、`~/Movies`、`~/Music`、`~/Public`、`~/Library/Mobile Documents`（iCloud Drive）
- 凭据与个人数据：`~/Library/Keychains`、`~/Library/Mail`、`~/Library/Messages`、`~/Library/Safari`（历史、书签）、`~/.ssh`、`~/.gnupg`、`~/.aws`、`~/.kube`、照片库（`*.photoslibrary`）
- Peek 自己：`~/Library/Application Support/Peek`，以及 Bundle ID 为 `cc.yuntianyou.peek`、`cc.yuntianyou.peek.dev` 的缓存、偏好、容器

**G3 不跟随符号链接。** 规则根路径本身是符号链接时整条跳过；扫描和删除过程中遇到符号链接，只把链接本身当一个条目（大小按链接自己算，删除也只删链接），**不进入它指向的目标**。同时对路径的物理位置（解析后的真实路径）再做一遍 G2 检查，防止通过链接绕过保护。

**G4 大小按实际占用，硬链接只算一次。** 用 `totalFileAllocatedSize`，取不到退回 `fileAllocatedSize`、`fileSize`。同一次扫描里按（设备号, inode）去重，同一个文件只计一次。释放空间统计以删除前扫描到的占用为准，不用磁盘剩余量的差值。

**G5 没权限静默跳过。** 读不了的目录、删不掉的文件，不弹错误；在明细里标"无权限"，不计入可回收总量，在结果汇总里计入"跳过"。

**G6 用户白名单。** 白名单里的路径，按路径组件前缀匹配（`/a/b` 保护 `/a/b` 和 `/a/b/c`，不保护 `/a/bc`）。命中的整棵子树不出现在扫描结果里，也不会被删。规范化路径和物理路径**都要**比对。白名单在扫描时和执行时各检查一次。

**G7 App 正在运行就跳过，判断不了也当作在运行。** 缓存目录的名字是反向域名（如 `com.example.App`）时，用 `NSWorkspace.shared.runningApplications` 的 bundle id 比对（含前缀关系，如 `com.example.App.helper` 属于 `com.example.App`）。命中就跳过这一项，原因写"App 正在运行"。拿不到运行列表时，当作所有 App 都在运行，整类跳过。浏览器、Xcode 等规则另有更明确的运行检查，见各自规则。

**G8 刚用过的不删。** 缓存和日志条目，最近 60 分钟内被修改过的跳过（原因"刚被使用"），避免删到正在写入的文件。

**G9 同一路径只出现在一个分类。** 一个路径同时符合多条规则时，归给更具体的规则（浏览器、开发工具优先于通用"用户缓存"），不重复列出、不重复计大小。

**G10 只处理启动卷。** 规则路径解析后必须和主目录在同一个卷上，否则跳过。v1 不清理外接盘、网络盘。

**G11 删除前重新校验。** 扫描结果只是预览。执行时对每一项重新做 G1–G8 的检查，并确认它还是扫描时的那个文件（类型和（设备号, inode）没变）。变了就跳过，原因"已变化"。

**G12 预览、确认、可取消。** 没有"静默自动清理"：必须先预览（分类、大小、条数、可展开看路径），用户勾选并点确认后才执行。扫描和执行都能取消；取消后已删的不回滚，结果里写明已处理多少。

**G13 记录历史。** 每次执行结束调用 `HistoryStore.shared.record(HistoryEntry(kind: .clean, ...))`，写入处理条数、释放字节数、失败数。

**G14 不主动触发系统授权弹窗。** 只在用户进入对应功能时才访问会弹窗的目录（`~/Downloads`、`~/Desktop`、`~/Documents`）。用户拒绝后该项跳过，不反复弹。

## 3. 保留清单（缓存里也不动的应用）

下面这些 bundle id 前缀对应的缓存目录，在 R1、F2 里**一律跳过**（原因"受保护的应用"）。它们要么是密码和凭据类，要么保存同步或连接状态，删了会让用户重新登录或重新同步，得不偿失。已按评审补充开发者类和通讯笔记类：

- 系统：`com.apple.*`（缓存里的 Apple 自带 App 一律不动；Xcode、Safari 由 R5、F1 点名处理）
- 密码和凭据：`com.1password`、`com.agilebits`、`com.bitwarden`、`org.keepassxc`、`com.lastpass`、`com.dashlane`
- VPN 和代理：`com.wireguard`、`net.mullvad`、`com.nordvpn`、`com.expressvpn`、`com.clash`、`com.surge`
- 云盘同步状态：`com.getdropbox.dropbox`、`com.microsoft.OneDrive`、`com.google.GoogleDrive`
- 虚拟机和容器运行时：`com.docker`、`com.orbstack`、`com.utmapp`、`com.parallels`、`com.vmware`
- 输入法：`im.rime`、`com.sogou`、`com.baidu.inputmethod`、`com.tencent.inputmethod`
- IDE 和编辑器：`com.jetbrains`、`com.microsoft.VSCode`、`com.visualstudio.code`、`com.sublimetext`、`com.sublimehq`、`com.panic.Nova`、`com.todesktop`（Cursor 等）、`com.exafunction.windsurf`（Xcode 属 `com.apple.*`，已在系统一行）
- AI 工具：`com.anthropic.claude`、`com.openai`、`com.ollama`、`com.lmstudio`
- 数据库客户端和抓包、API 工具：`com.sequel-ace`、`com.sequelpro`、`com.dbeaver`、`com.navicat`、`com.mongodb.compass`、`com.postmanlabs`、`com.konghq.insomnia`、`com.proxyman`、`com.charlesproxy`、`com.usebruno`
- Git 和终端：`com.github.GitHubDesktop`、`com.fork.Fork`、`com.git-tower`、`com.axosoft.gitkraken`、`com.googlecode.iterm2`、`net.kovidgoyal.kitty`、`io.alacritty`、`com.github.wez.wezterm`、`dev.warp`
- 通讯和笔记（缓存里常带登录态或本地索引）：`com.tencent.xinWeChat`、`com.tencent.qq`、`com.tencent.WeWorkMac`、`ru.keepcoder.Telegram`、`com.tdesktop.Telegram`、`com.tinyspeck.slackmacgap`、`com.hnc.Discord`、`com.microsoft.teams`、`com.electron.lark`、`notion.id`、`md.obsidian`、`com.evernote`
- 浏览器**不**放进保留清单：它们的缓存由 R4 单独规定，只清缓存目录，不碰 Cookie 和登录数据
- 匹配只用 bundle id 前缀，不用名字通配，避免误伤同名片段的无关应用
- 无条件保护的缓存子目录名：`CloudKit`

## 4. 分类规则

### R1 用户缓存

| 项 | 规则 |
|---|---|
| 路径 | `~/Library/Caches/<名称>/` 下的内容，每个 `<名称>` 作为一组展示 |
| 保留条件 | 保留 `<名称>` 目录本身，只删里面的内容（应用会自己重建）；G8 的 60 分钟规则 |
| 跳过条件 | 保留清单（第 3 节）；G7 App 正在运行；已归入 R4、R5 的目录（G9）；`~/Library/Caches` 下不是目录的零散文件 |
| 删除方式 | 直接删 |
| 需要 FDA | 否 |
| 默认勾选 | 是 |
| 丢数据吗 | 不丢。缓存可重建；最坏是应用下次启动变慢，或要重新下载缩略图 |

### R2 日志

| 项 | 规则 |
|---|---|
| 路径 | `~/Library/Logs/` 下的文件，含 `DiagnosticReports`（崩溃报告） |
| 保留条件 | 只删最后修改**超过 7 天**的文件；目录结构保留 |
| 跳过条件 | G8；`~/Library/Logs` 里属于 Peek 的日志；保留清单对应应用的日志目录 |
| 删除方式 | 直接删 |
| 需要 FDA | 否 |
| 默认勾选 | 是 |
| 丢数据吗 | 不丢用户数据。会丢 7 天前的诊断信息，排查旧问题时可能想看，所以保留最近 7 天 |

### R3 窗口状态

| 项 | 规则 |
|---|---|
| 路径 | `~/Library/Saved Application State/<bundle id>.savedState` |
| 保留条件 | 只删最后修改**超过 30 天**的 |
| 跳过条件 | 对应 App 正在运行（G7）；G8 |
| 删除方式 | 直接删 |
| 需要 FDA | 否 |
| 默认勾选 | 是 |
| 丢数据吗 | 不丢文档内容。会丢"上次关闭时窗口的位置和打开了哪些窗口"，下次启动回到默认窗口 |

与 PEEK-9（系统维护）里的"清理窗口状态"是同一个规则，**共用同一份实现**，不要写两份。两处各自写历史记录。

### R4 浏览器缓存（不含 Safari）

只删缓存目录，**不碰** Cookies、历史记录、登录数据（Login Data）、本地存储（Local Storage、IndexedDB）、扩展、书签、会话。

| 浏览器 | 路径 |
|---|---|
| Chrome | `~/Library/Caches/Google/Chrome/*`；`~/Library/Application Support/Google/Chrome/<Profile>/` 下的 `Cache`、`Code Cache`、`GPUCache`、`Service Worker/CacheStorage` |
| Edge | `~/Library/Caches/Microsoft Edge/*`；`~/Library/Application Support/Microsoft Edge/<Profile>/` 下同样四个目录 |
| Brave | `~/Library/Caches/BraveSoftware/Brave-Browser/*`；`~/Library/Application Support/BraveSoftware/Brave-Browser/<Profile>/` 下同样四个目录 |
| Arc | `~/Library/Caches/company.thebrowser.Browser/*`；`~/Library/Application Support/Arc/User Data/<Profile>/` 下同样四个目录 |
| Firefox | `~/Library/Caches/Firefox/Profiles/*/cache2`（只这一个子目录） |

`<Profile>` 指 `Default` 和 `Profile N`，不展开其他目录。

| 项 | 规则 |
|---|---|
| 保留条件 | 保留缓存目录本身，只删内容 |
| 跳过条件 | 该浏览器**正在运行**（按 bundle id 判断，不用 G7 的前缀宽松匹配；原因"浏览器正在运行，请先退出"）；G8 |
| 删除方式 | 直接删 |
| 需要 FDA | 否 |
| 默认勾选 | 是 |
| 丢数据吗 | 不丢。网页需要重新加载；不会退出登录（Cookies 不动） |

### R5 开发工具

默认勾选，直接删，或调用工具自己的命令。每个工具独立成一行，用户可单独取消勾选。工具命令不存在时：下表写了"直接删"的按直接删处理；写了"仅工具命令"的整行跳过（原因"工具未安装"）。**所有命令不可能需要管理员权限**，设 120 秒超时。

| 工具 | 路径 | 方式 | 说明 |
|---|---|---|---|
| npm | `~/.npm/_cacache`、`~/.npm/_logs` | `npm cache clean --force`（`npm` 存在时），否则直接删 `_cacache` | 可重建 |
| pnpm | store 目录（用 `pnpm store path` 取；取不到则跳过） | `pnpm store prune`，仅工具命令 | 只清没被任何项目引用的包，不会破坏现有 `node_modules` |
| Yarn classic | `~/Library/Caches/Yarn` | 直接删 | |
| Yarn Berry | `~/.yarn/berry` | **永远不动** | 全局归档库可能被零安装、PnP 项目离线依赖，删了会让这些项目装不起来 |
| pip | `~/Library/Caches/pip` | `pip3 cache purge`（存在时），否则直接删 | |
| uv | `~/.cache/uv` | `uv cache clean`，仅工具命令 | |
| Go | `~/Library/Caches/go-build` | `go clean -cache`，仅工具命令 | **不动** `~/go/pkg/mod`（模块缓存，离线构建要用） |
| Homebrew | `~/Library/Caches/Homebrew/downloads` | `brew cleanup --prune=all`（`brew` 存在时），否则直接删 `downloads` 下的文件 | 不卸载任何已装的包 |
| CocoaPods | `~/Library/Caches/CocoaPods` | 直接删 | |
| Gradle | `~/.gradle/caches` | 直接删 | 有 Gradle 进程在运行（进程名含 `gradle`、`GradleDaemon`）时跳过；判断不了也跳过 |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | 直接删 | Xcode 正在运行时跳过（原因"Xcode 正在运行"） |
| Xcode DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport/*`，以及 `watchOS DeviceSupport`、`tvOS DeviceSupport`、`visionOS DeviceSupport` | 直接删 | 每种平台**保留版本号最新的一个目录**，其余才删。下次连接设备时系统会重新下载符号，较慢但不丢东西 |
| 不可用的模拟器 | `~/Library/Developer/CoreSimulator/Devices/<UDID>`（仅不可用的） | `xcrun simctl delete unavailable`，仅工具命令 | 先用 `xcrun simctl list devices unavailable -j` 取清单做预览，大小按这些设备目录算 |

> **v1 暂不实现“不可用的模拟器”这一行**：`xcrun` 在 CoreSimulator 组件过旧的机器上会触发系统“安装 Apple 软件”的弹窗，违反 G14。要做的话必须先能不经 `xcrun` 判断组件是否健康。上面那一行规则保留，作为以后的设计。


**明确不动**（在 G2 之外再强调一遍，因为它们容易被误当成缓存）：`~/Library/Developer/Xcode/Archives`（打包产物）、`~/Library/Developer/Xcode/UserData`、`~/Library/Developer/CoreSimulator/Devices/` 里可用的模拟器（里面有 App 数据）、`~/.yarn/berry`、`~/go/pkg/mod`、Jupyter 的运行时目录（`jupyter --runtime-dir`，里面是活动连接信息）、conda 和 pyenv 的环境目录。

丢数据吗：不丢。均可重新下载或重新构建；代价是下次构建或装依赖变慢。

### R6 已卸载 App 的残留

这是误删风险最高的一类，规则最严。**宁可漏掉，不能错删。**

| 项 | 规则 |
|---|---|
| 扫描位置 | `~/Library/Application Support`、`~/Library/Preferences`（`<id>.plist`）、`~/Library/HTTPStorages`、`~/Library/Saved Application State`、`~/Library/WebKit`、`~/Library/Cookies`、`~/Library/Logs`、`~/Library/Caches` 下，名字是反向域名的条目 |
| 如何判定"对应 App 已不存在" | 条目名（去掉 `.plist`、`.savedState`、`.binarycookies` 等后缀）是反向域名格式（至少两个点，全部字符为字母数字、`-`、`_`、`.`）；**并且**用以下方式都找不到这个 bundle id 的 App：LaunchServices（`LSCopyApplicationURLsForBundleIdentifier`）；扫描 `/Applications`、`/Applications/Utilities`、`/System/Applications`、`~/Applications`、`/Applications/Setapp` 里所有 `.app` 的 `Info.plist` |
| 只按 bundle id 匹配 | **不按 App 名字匹配**（如 `Application Support/Slack`、`Code`）。名字太容易撞到仍在使用的数据。按名字找残留只在用户主动卸载某个 App 时做，见 PEEK-8 |
| 同族保护 | 只要系统里还有任何 App，它的 bundle id 和候选条目的 id 是"点分前缀关系"（任一方是另一方加上 `.xxx`），整条跳过。例如装着 `com.foo.App`，就不动 `com.foo.App.helper` 和 `com.foo.App.beta` |
| 保留条件 | 条目（含里面所有文件）最后修改**超过 30 天** |
| 跳过条件 | `com.apple.*`；保留清单（第 3 节）；G7；G2；扫描 App 列表时有任何目录读不了或超时（App 清单不完整）则整个 R6 跳过 |
| 不碰 | `~/Library/Containers`、`~/Library/Group Containers`（共享，且需要 FDA）；`/Library` 下的系统级残留（需要管理员权限，v1 不做） |
| 删除方式 | **废纸篓** |
| 需要 FDA | 否 |
| 默认勾选 | 是 |
| 丢数据吗 | 可能。已卸载 App 的 `Application Support` 里有时有用户数据（存档、本地库、授权）。所以必须走废纸篓，且在预览里把 `Application Support` 里的条目单独标出，让用户知道。其余（偏好、HTTP 存储、缓存）不丢用户内容 |

### R7 项目构建产物

| 项 | 规则 |
|---|---|
| 扫描目录 | 设置里配置（PEEK-10）。默认只扫存在的这些：`~/Developer`、`~/Projects`、`~/Code`、`~/work`、`~/dev`、`~/src`、`~/GitHub`。不默认扫 `~/Documents`、`~/Desktop`（会触发授权弹窗，G14） |
| 扫描方式 | 最深 6 层；不跟随符号链接；不进入 `.git`；不进入已识别的产物目录内部（不找嵌套的 `node_modules`）；跳过隐藏的系统目录 |
| 如何识别 | 目录名命中下表，**并且**同级有对应的"工程标记"文件，缺一不可 |
| 保留条件 | 工程最近 **7 天内有改动**的不列。判定：工程根目录下除产物自身外的直接子项里，最新的修改时间在 7 天内；或产物目录本身最近 7 天内被改过 |
| 跳过条件 | G2、G3、G6；产物目录是符号链接 |
| 删除方式 | 直接删 |
| 需要 FDA | 否 |
| 默认勾选 | **否** |
| 丢数据吗 | 不丢源码。产物可重新构建；代价是下次构建要重新下载依赖和编译，离线时可能装不回来，所以默认不勾选 |

| 目录名 | 同级必须有 |
|---|---|
| `node_modules` | `package.json` |
| `target` | `Cargo.toml` 或 `pom.xml` |
| `.build` | `Package.swift` |
| `Pods` | `Podfile` |
| `build` | `build.gradle`、`build.gradle.kts` 或 `CMakeLists.txt` |
| `dist` | `package.json`，并且同级 `.gitignore` 里有一行精确写着 `dist`、`dist/` 或 `/dist`（避免删掉被提交到仓库的发布文件） |
| `.venv`、`venv` | 目录里有 `pyvenv.cfg` |

不识别 `build`、`dist` 以外的通用名字（如 `out`、`bin`、`lib`、`vendor`）。不调用 `git`（避免命令行工具缺失时系统弹安装窗口）。

### R8 安装包

| 项 | 规则 |
|---|---|
| 路径 | `~/Downloads` **顶层**的文件，扩展名（不分大小写）`.dmg`、`.pkg`、`.iso`、`.xip`。v1 不递归子目录 |
| 保留条件 | 最后修改超过 24 小时（避开刚下完、可能马上要装的） |
| 跳过条件 | 同名带 `.download`、`.crdownload`、`.part` 后缀的文件还在（正在下载）；文件被某进程打开着（读不出来就当作打开着）；用户拒绝了"下载"目录的授权（G14） |
| 删除方式 | **废纸篓** |
| 需要 FDA | 否（需要"下载"文件夹授权，首次访问时系统弹窗） |
| 默认勾选 | **否** |
| 丢数据吗 | 不丢你的文档，但安装包可能是你特意留着的离线安装包（下载不到了的旧版本）。所以走废纸篓，默认不勾选 |

### R9 废纸篓

| 项 | 规则 |
|---|---|
| 做法 | 通过 Finder 清空：`tell application "Finder" to empty the trash` |
| 大小显示 | 需要 FDA 才能读 `~/.Trash`；没有 FDA 时只显示"清空废纸篓"，不显示大小 |
| 删除方式 | Finder 清空（**不可恢复**） |
| 需要 FDA | 显示大小需要；清空本身不需要，但需要"自动化"授权（首次弹窗）。用户拒绝则跳过 |
| 默认勾选 | **否** |
| 丢数据吗 | **会，而且不可恢复**。这是 Peek 里唯一不可恢复的清理动作，必须在确认框里单独写明，不和别的项混在一个确认里一笔带过 |

## 5. 授予完全磁盘访问后增加的分类

没有授权时这些分类不出现，面板和设置里只提示一行"授权后可多清理哪些内容"，不报错。

### F1 Safari 缓存

| 项 | 规则 |
|---|---|
| 路径 | `~/Library/Caches/com.apple.Safari` 下的 `WebKitCache`、`fsCachedData`、`Webpage Previews` 三个子目录的内容 |
| 不碰 | `~/Library/Safari`（历史、书签、阅读列表）；`Cookies` |
| 跳过条件 | Safari 正在运行（原因"Safari 正在运行，请先退出"）；G8 |
| 删除方式 | 直接删 |
| 默认勾选 | 是 |
| 丢数据吗 | 不丢。网页需要重新加载 |

### F2 沙盒 App 缓存

| 项 | 规则 |
|---|---|
| 路径 | `~/Library/Containers/<bundle id>/Data/Library/Caches/` 下的内容 |
| 保留条件 | 保留 `Caches` 目录本身，只删里面的内容 |
| 跳过条件 | 保留清单；G7；G8；**只碰 `Data/Library/Caches` 这一层**，不碰容器里的其他任何目录（`Documents`、`Application Support`、Docker 等运行时的数据） |
| 删除方式 | 直接删 |
| 默认勾选 | 是 |
| 丢数据吗 | 不丢。同 R1 |

## 6. 实现提示（给开发的人）

- 每条规则实现成一个遵循统一接口的小类型，输入是"根路径集合 + 全局上下文（白名单、运行 App 列表、当前时间）"，输出是候选条目列表（规则 id、路径、占用、类型、（设备号, inode）、跳过原因）。**根路径要能注入**，这样才能在临时目录里造数据测试。
- 把 G1–G11 的检查收口到**一个**判定函数，扫描和执行都调它，不要各规则自己写一份。
- 删除执行层只有一个入口：接收"候选条目"，做 G11 重新校验，再按删除方式执行，返回每一项的结果。别的地方不直接调用 `removeItem`。
- 测试方法：单元测试用临时目录造数据，覆盖：符号链接指向保护路径、硬链接去重、无权限目录、白名单前缀匹配（`/a/b` 和 `/a/bc`）、60 分钟、7 天、30 天边界、App 正在运行、扫描后文件被换成别的东西（G11）。**真机测试先看预览，不要直接清自己的真实缓存。**

## 7. 评审时需要确认的决定

下面是我替你定下的首版取值，评审时请确认或修改：

1. 缓存、日志"刚被使用"的保护时间取 60 分钟（G8）；日志保留 7 天（R2）。
2. R6 残留要求超过 30 天未修改；`Application Support` 里的条目在预览中单独标出。
3. R7 的默认扫描目录列表，以及 `dist` 需要 `.gitignore` 佐证才识别。
4. R5 里 Gradle 缓存、Xcode DeviceSupport（保留最新一个）、`pnpm store prune` 的处理方式。
5. 第 3 节保留清单：已定，补开发者类（IDE、AI、数据库抓包、Git 终端）和通讯笔记类，浏览器不保护。
6. R8 保留 24 小时、不递归子目录。
