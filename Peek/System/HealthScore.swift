import Foundation

/// 健康等级。颜色由皮肤决定，这里只给等级。公式见 `docs/health-score.md`。
enum HealthGrade: Sendable, Equatable {
    case excellent
    case good
    case fair
    case poor

    init(score: Int) {
        switch score {
        case 90...: self = .excellent
        case 75...: self = .good
        case 55...: self = .fair
        default: self = .poor
        }
    }
}

/// 0–100 的健康分。
struct HealthScore: Sendable, Equatable {
    var value: Int
    var grade: HealthGrade

    /// 按 `docs/health-score.md` 的公式计算。
    /// - Parameter cpuSustained: 最近一分钟的平均 CPU 占用，0...1。采集器负责维护这个滑动平均。
    static func compute(snapshot s: SystemSnapshot, cpuSustained: Double) -> HealthScore {
        func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

        // CPU：持续占用超过 50% 开始扣分，满载扣 25。
        let cpuPenalty = clamp01((cpuSustained - 0.5) / 0.5) * 25

        // 内存：压力等级扣 0 / 12 / 25；已用超过 85% 另扣最多 10。
        let pressurePenalty: Double = switch s.memory.pressure {
        case .normal: 0
        case .warning: 12
        case .critical: 25
        }
        let usedPenalty = clamp01((s.memory.usedFraction - 0.85) / 0.15) * 10
        let memoryPenalty = pressurePenalty + usedPenalty

        // 磁盘：余量低于 20% 开始扣分，余量为 0 扣 25。
        let diskPenalty = clamp01((0.20 - s.disk.freeFraction) / 0.20) * 25

        // 运行时长：超过 14 天开始扣分，30 天及以上扣 10。
        let days = s.uptime / 86_400
        let uptimePenalty = clamp01((days - 14) / 16) * 10

        let raw = 100 - cpuPenalty - memoryPenalty - diskPenalty - uptimePenalty
        let value = Int(min(100, max(0, raw)).rounded())
        return HealthScore(value: value, grade: HealthGrade(score: value))
    }
}
