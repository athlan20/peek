# History

清理、卸载、维护的本地历史记录，见 PEEK-6。数据格式带版本号，改格式要兼容旧数据。

文件格式（`~/Library/Application Support/Peek/history.json`，正式版和开发版共用）：

```json
{"version": 1, "entries": [{"id": "…", "date": "2026-01-01T00:00:00Z", "kind": "clean", "itemCount": 12, "freedBytes": 1024, "failedCount": 0, "note": null}]}
```

- 日期用 ISO8601。读到更高的 `version` 只读不写；损坏的文件备份为 `history.json.corrupt-<时间戳>`。只保留最近 500 条，写入时先读磁盘再追加并原子替换。
- `HistoryStore(fileURL:)`：`record(_:)` 追加，`recent(_:)` 取最近几条，`lastCleaned` 是最近一次清理时间。`lastCleanedText(_:now:)` 生成 Clean 窗口顶部“距上次清理多久”的文案。
- 累计计数单独存同目录的 `history-totals.json`：`HistoryTotals` 记清理总量、卸载和优化的项数，`HistoryStore.totals` 在 `record` 里更新内存，后台“读最新 → 累加 → 原子写入”，避免两个进程互相覆盖。
- 该文件不存在或损坏时，用现有 `history.json` 的条目一次性初始化（seed）并写盘。只保留 500 条记录，所以累计值不能从 `entries` 求和。
