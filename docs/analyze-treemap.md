# Analyze 方块视图(PEEK-19)

磁盘分析窗口"文件"页的另一种视图:当前文件夹的直接子项画成 treemap,方块面积就是占用大小。只看一层,双击文件夹方块进入,面包屑返回。数据就是列表视图的那份扫描结果,切换视图不重新扫描。

## 布局

- 算法:squarified treemap(Bruls 等,2000),子项按大小从大到小排列,尽量让方块接近正方形。
- 方块数量上限 80。占当前总量不到 0.2% 的子项,以及排在 80 名以后的,合并成一个"其他"方块,标出合并了几项;只剩 1 项时不合并。
- 大小为 0 的子项(含无权限目录)不画。不显示图例,颜色含义靠方块上的文字和悬停提示。
- 方块之间留 1pt 缝。方块够大才写字:宽 ≥ 44pt、高 ≥ 28pt 写名称,高 ≥ 42pt 再写大小;字号随方块大小分三档。放不下字的方块只画色块,悬停显示名称、大小、路径。

## 边扫边画

扫描一开始就画方块，不等扫完。扫描器每 0.2 秒给一份中途快照：扫完的子项按最终大小，正在扫的那个按目前量到的大小，还没轮到的不画。方块随快照平滑长大、重排（0.3 秒缓动），扫完换成最终结果。列表视图同样边扫边更新。

- 扫到一半时可以点进已经出现的文件夹；这一层的扫描停在检查点上，返回时接着扫。
- Agent 页第一层在量完之前不能点进某个 Agent（它各目录的数还没出来）。
- 页签行右边有暂停 / 继续按钮,再右边是刷新按钮。暂停见下面"暂停和接着扫"。

## 交互

- 单击选中(白色描边),双击文件夹进入下一层,双击文件在 Finder 中显示。
- 底部"在 Finder 中显示""移到废纸篓"对选中的方块生效,跟列表视图共用同一个选中项和确认流程。
- 右键方块(列表视图右键行也一样)弹菜单:"在访达中显示"、"删除…"。删除走和底部按钮同一个二次确认,确认后移到废纸篓,不直接抹掉。"其他"方块没有菜单。Agent 页第一层的 Agent 块量完后也有这个菜单,见下文。
- "其他"方块不能选中,双击切到列表视图看全部子项。
- 视图选择(方块 / 列表)记在偏好设置里,键 `analyze.layout`。"下载"页始终是列表。

## Agent 页

页签"文件 / Agent / 下载"(原来的"大文件"页去掉了;"下载"页内容不变,仍是 `~/Downloads` 里 90 天没动过的条目)里的"Agent"页,只看 AI Agent 的文件,方块 / 列表切换同样适用。

- 第一层:每个 Agent 一块,大小是它在下面识别表里所有目录之和。不存在的目录跳过,合计为 0 的 Agent 不列。第一次切到这页时才扫描,结果缓存到窗口关闭。
- 第二层:点进某个 Agent,列出它在磁盘上的各个目录(如 `~/.claude`、`~/Library/Caches/Claude`),不重新扫描。
- 第三层起:就是普通的逐层分析。
- 第一层的 Agent 块对应它量到的所有目录:"在访达中显示"一次选中这些目录;"删除…"把这些目录逐个移到废纸篓,确认框列出全部目录并提醒里面有设置和登录信息。量完之前没有菜单。第二层起和"文件"页一样。
- "文件"页和"Agent"页各有一套导航和扫描,切换页签互不打断。"选择位置"总是回到"文件"页打开。

## 窗口布局

从上到下:返回和面包屑 / 页签行 / 状态行 / 内容 / 底部按钮。

- 页签行:左边"文件 / Agent / 下载"页签;右边是"选择位置"下拉(只在"文件"页出现),再右边是扫描中的暂停/继续按钮,或扫完后的刷新按钮。
- 状态行:左边"正在扫描…"或"总计 X · N 分钟前扫描";右边方块/列表切换(逐层的两页才有)。

## 记住上次的结果

扫完的结果存进 `~/Library/Caches/Peek/analyze-cache.json`,关窗口、重启 Peek 后再打开,扫过的位置直接显示上次的方块,不重扫。

- 记的是:"文件"页每一层扫完的目录(最多 200 层,超出丢最早的;子项超过 5000 个的目录不记)、"Agent"页的量出结果、"下载"页的结果。
- 状态行写"总计 X · N 分钟前扫描",右边有刷新按钮,点了重扫当前这一层(上级不动)。在某个 Agent 的目录列表里刷新,只重量这个 Agent,第一层它的块跟着变。"下载"页刷新重扫下载。
- 移到废纸篓后,缓存里对应的条目一起去掉、上级总量减掉。
- 只是缓存:读不出或版本不对就当没有,重扫即可。格式变了升版本号,旧文件自动作废。各 worktree 的开发版和正式版共用这一份。
- 缓存不会自己过期:磁盘上后来的变化(别处删了、新增了文件)要点刷新才反映出来。

## 暂停和接着扫

扫描可以停在检查点上,之后从那里接着扫,不用从头来。检查点和停下时界面上的方块一起存进缓存,重启 Peek 后也在。

- **检查点记什么**:第一层扫完的子项(含最终大小);正在扫的那个子项里,沿当前递归路径每层目录"哪些子项量完了、合计多少"。接着扫时跳过这些,正在量的那个最深的文件夹从头量。列一个目录本身不拆开。
- **什么时候停在检查点**:点暂停;离开正在扫的这一层(点进下一层、回上级、换位置);关窗口。
- **什么时候接着扫**:点继续;回到停下的那一层;再打开窗口(用户自己暂停的也在下次打开时自动继续,这次窗口里保持暂停)。
- **刷新**:丢掉这一层的结果和检查点,从头扫。扫描中、暂停中都能点。
- "Agent"页第一层同样能停能接着量,检查点按 Agent、目录记。在某个 Agent 的目录列表里刷新(只量这一个 Agent)停下的位置只记在内存里。"下载"页不能暂停。
- 移到废纸篓后,检查点里记的也去掉,接着扫时不会算回来。
- 已知误差:硬链接去重只在一次扫描内有效,停过再接着扫时前后两段之间的硬链接可能重复计算;停下期间磁盘上的变化,已经量完的部分不会反映,要点刷新。

## 关闭窗口

关掉分析窗口时所有扫描停在检查点上(下载页的扫描直接取消),不在后台继续读盘。下次打开窗口时接着扫。

## 颜色

先判断是不是 AI Agent 的目录,是就用 Agent 色;否则按类型着色。颜色都是压暗过的,深浅色模式下都用白字。

### Agent 识别表

条目路径等于下表某个路径,或在它里面,就算这个 Agent。路径相对主目录。只有公认的品牌主色才写主题色,其余用统一的"AI Agent"色,方块上写 Agent 名字区分。

| Agent | 路径 | 主题色 |
|---|---|---|
| Claude Code / Claude | `.claude`、`.local/share/claude`、`Library/Application Support/Claude`、`Library/Caches/Claude` | `#D97757` |
| Codex | `.codex`、`Library/Application Support/Codex`、`Library/Caches/Codex` | `#10A37F` |
| Gemini CLI | `.gemini` | `#4796E3` |
| Hugging Face | `.cache/huggingface` | `#FFD21E` |
| Cursor | `.cursor`、`.local/share/cursor-agent`、`Library/Application Support/Cursor` | — |
| GitHub Copilot | `.copilot` | — |
| opencode | `.opencode`、`.local/share/opencode`、`.config/opencode` | — |
| Ollama | `.ollama` | — |
| LM Studio | `.lmstudio`、`.cache/lm-studio` | — |
| Windsurf | `.windsurf`、`.codeium`、`Library/Application Support/Windsurf` | — |
| Kiro | `.kiro`、`Library/Application Support/Kiro` | — |
| Trae | `.trae`、`Library/Application Support/Trae` | — |
| Continue | `.continue` | — |
| Aider | `.aider` | — |
| Qwen Code | `.qwen` | — |
| T3 Code | `.t3` | — |
| pi | `.pi` | — |
| WorkBuddy | `.workbuddy`、`.workbuddy-ai`、`Library/Application Support/WorkBuddy`、`Library/Application Support/com.tencent.workbuddy.mac`、`Library/Caches/com.tencent.workbuddy.mac`、`Library/Caches/com.tencent.workbuddy.mac.BundleMigration` | — |
| CodeBuddy | `.codebuddy`、`.codebuddycn`、`Library/Application Support/CodeBuddy CN`、`Library/Application Support/CodeBuddyExtension` | — |

加新工具只改 `AnalyzeClassifier.agents` 和这张表。

### 类型

按顺序取第一个命中的:

1. **AI Agent**:命中上表。
2. **应用**:`.app` 包,或在 `/Applications`、`~/Applications` 里。
3. **开发**:路径里有 `node_modules`、`DerivedData`、`.npm`、`.cargo`、`.gradle`、`.m2` 等开发工具目录,或者是主目录下的 `Developer`、`work`、`Projects`、`GitHub`、`dev`、`code`、`go`、`.cache`、`.docker`、`.vscode` 等。
4. **媒体**:主目录下的 `Movies`、`Music`、`Pictures`,或图片、视频、音频、照片图库文件。
5. **文档**:主目录下的 `Documents`、`Desktop`、`Downloads`,或 PDF、Office、iWork、文本、压缩包、安装包文件。
6. **系统与资源库**:`~/Library`,或启动盘根下的 `System`、`Library`、`private`、`usr` 等。
7. **其他**。

## 删除确认文案

右键"删除…"和底部"移到废纸篓"弹同一个确认框。标题"删除「名字」？",按钮"移到废纸篓"(红)和"取消"。正文先说删什么、多大、在哪,再提醒用户自己判断,最后说明能恢复:

- 普通条目:`大小 · ~/路径` / 请自己确认这是不再需要的内容。Peek 只按大小列出，不判断能不能删。/ 会移到废纸篓，清倒废纸篓之前都能恢复。
- Agent 块:以下文件夹会移到废纸篓（共 X）:逐行列出目录和大小 / 里面有 某 Agent 的设置、登录信息和会话记录。删除后需要重新登录，历史会话也会消失。请自己确认不再需要它们。/ 清倒废纸篓之前都能恢复。

## 公共组件

画方块的部分是公共组件，放在 `Peek/Treemap/`，清理(分类 → 组)和卸载(App)以后复用。磁盘分析只负责把 `AnalyzeItem` 转成方块数据，"画"和"点击"都由公共组件做。

- `TreemapLayout`(`TreemapLayout.swift`):纯计算。squarified 布局、方块数量上限、不到 0.2% 的并进"其他"的规则都在这里。
- `TreemapEntry` / `TreemapTiles`(`TreemapEntry.swift`、`TreemapTiles.swift`):一项方块数据，以及"条目 → 要画的方块"的纯函数(过滤、排序、"其他"合并)，不依赖视图，可以直接单元测试。
- `TreemapView`(`TreemapView.swift`):视图。方块颜色、标题、副标题、悬停提示、可访问名称和右键菜单都由调用方给，组件里不写界面文案。
- 调用方决定单双击做什么、要不要选中(`selectedID` 传 `nil` 就没有白框)。"其他"方块单击、双击也是调用方的回调，不传就什么也不做。
- `isDimmed` 把方块压暗，用于不可用、未勾选。要分强度时用 `dimLevel`(`TreemapDim`:`.none`、`.light`、`.strong`)，`isDimmed` 的语义不变(等于 `.strong`);两样都传时以 `dimLevel` 为准。`.light` 是黑色 0.18 蒙层(只是暂时不能操作，如 App 正在运行)，`.strong` 是 0.45(明显不可用)。
- `badge` 是方块右上角的小图标，不挤文字：`.check`(全选)、`.halfCheck`(部分选中)、`.lock`(不可用)、`.warning`(橙色，提醒注意)、`.running`(正在运行，`play.circle.fill`)。
- `icon` 是方块里的图标(磁盘分析不传,卸载窗口传 App 图标)。画什么由纯函数 `TreemapTileLayoutMode.mode(width:height:hasIcon:)` 决定,不依赖视图、可以直接单元测试:
  - **有图标,方块宽 ≥ 60pt 且高 ≥ 84pt**:图标在上,名称、大小(和副标题)在下,垂直排开、整体居中,图标和文字间距 4pt。图标分两档:宽 ≥ 180pt 且高 ≥ 110pt 用 40pt,否则 32pt。文字的三档字号和行数规则不变。
  - **有图标,放不下"图标 + 文字"、但文字放得下**(宽 ≥ 44pt、高 ≥ 28pt):只画文字,不画图标。
  - **文字也放不下,宽高都 ≥ 24pt**:只画图标,20pt,名称看悬停提示。
  - **没有图标**(磁盘分析不传):和加图标之前完全一样,文字放得下就写,放不下只留色块。
  - 以上都不满足:只留色块。
- 图标、文字都画在方块中间,选中白框、悬停高亮照旧;右上角徽标(`badge`)盖在最上层,不会被内容挡住。
- `minFraction` 是并进"其他"的最小占比，`TreemapTiles.make` 和 `TreemapView` 都有，默认 `TreemapLayout.minFraction`(0.2%)，现有调用不用改。卸载窗口传 0，只留 80 块的数量上限，免得几十 MB 的小 App 全进"其他"(见 `docs/uninstall-treemap.md`)。
- **大小为 0 的项不画**。调用方要显示这些项，自己另列(磁盘分析就不列)。
