# Settings

设置独立窗口，见 PEEK-10。面板右上角的齿轮打开（`DestinationWindow` 的 `.settings` 分支）。

文件分工：

- `SettingsStore.swift`：所有设置项的读写，不依赖 UI。`UserDefaults` 可注入；路径统一走 `CleanGuard.normalized` 规范化并去重；刷新间隔读不到有效值时回退到 1 秒。
- `SettingsModel.swift`：`@MainActor` 状态，处理选择文件/文件夹、完全磁盘访问探测、开机启动（`SMAppService.mainApp`），刷新间隔改完调用 `SystemMonitor.restartTimer()`。
- `SettingsView.swift`：极简 `Form` 界面，分区为皮肤、清理白名单、项目扫描目录、刷新间隔、完全磁盘访问、开机启动、最近历史。
- 测试：`PeekTests/SettingsStoreTests.swift`（临时 suite，不碰真实用户设置）。