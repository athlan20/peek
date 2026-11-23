# System

系统状态采集（CPU、内存、磁盘、网络、电池、进程）和健康分计算，见 PEEK-2。只用系统接口，不需要额外权限。

## 数据口径与文件分工

| 项 | 接口 | 口径 |
|---|---|---|
| CPU | `host_processor_info`、`getloadavg` | 每核 user+system+nice 与 idle 的 tick 差；负载是 1/5/15 分钟均值 |
| 内存 | `host_statistics64`、sysctl | 已用 = App 内存（internal − purgeable）+ 联动 + 被压缩，对齐活动监视器的“已使用内存”（见 `MemorySampler` 注释）；压力取 `kern.memorystatus_vm_pressure_level` |
| 磁盘 | `URLResourceValues`、IOKit `IOBlockStorageDriver` | 已用 = 总量 − `volumeAvailableCapacityForImportantUsage`，与“关于本机 → 储存空间”同源；读写速度是累计字节做差 |
| 网络 | `getifaddrs`、`SCDynamicStore` | 只算默认网卡（`State:/Network/Global/IPv4` 的 `PrimaryInterface`），32 位计数按回绕处理 |
| 电池 | `IOPSCopyPowerSourcesInfo`、`AppleSmartBattery` | 内部电池的电量/充电状态；健康度读不到时为 nil；无电池返回 nil |
| 进程 | `proc_listpids`、`proc_pidinfo(PROC_PIDTASKINFO)` | CPU 时间按 mach timebase 换算，单核满载算 1.0；只在面板打开时 5 秒算一次 |

文件分工：`*Sampler.swift` 各管一项，`SamplingEngine`（actor）在后台组合采样并维护 60 秒 CPU 滑动平均，`SystemMonitor`（`@MainActor`）只管定时和把结果搬回主线程，`SystemSnapshot` 是数据模型，`HealthScore` 是健康分公式。

`SystemInfo` 是只读一次的系统静态信息（芯片名、内存容量、macOS 版本）；`SampleHistory` 是面板趋势小图用的固定容量样本缓冲，只在面板打开时追加，不落盘。