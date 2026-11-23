# Analyze

磁盘分析窗口，见 PEEK-7。

文件分工：`AnalyzeScanner` 是无 UI 的同步扫描器（可直接用小命令行程序测），`AnalyzeModel`（`@MainActor`）管目录栈、后台任务与取消，`AnalyzeView` 是极简 SwiftUI 界面。扫描规则：大小用磁盘实际占用；不跟随符号链接；硬链接按 `(设备号, inode)` 单次去重；文件夹为子项递归和；无权限目录标“无权限”且不计入总量；扫启动盘 `/` 时跳过 `/System/Volumes`、`/Volumes`、`/dev`、`/private/var/vm`。大文件 ≥100 MB、最多 50 个；旧下载只看 `~/Downloads` 一层里修改时间超过 90 天的项目。双击文件夹进入，双击文件在 Finder 中显示。
