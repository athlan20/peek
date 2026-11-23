import SwiftUI

/// 新主面板的暗色 Bento 视觉样式。后续接入皮肤系统时可由 Skin 提供这些颜色。
enum PanelPalette {
    static let panelBackground = Color(red: 0.075, green: 0.095, blue: 0.135)
    static let cardBackground = Color(red: 0.095, green: 0.118, blue: 0.165)
    static let overlayBackground = Color(red: 0.075, green: 0.095, blue: 0.140)
    static let inactivePixel = Color(red: 0.14, green: 0.19, blue: 0.27)
    static let trackBackground = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.09)

    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.64)
    static let textMuted = Color.white.opacity(0.45)

    // 告警强调色
    static let alertAccent = Color(red: 0.98, green: 0.34, blue: 0.32)
    static let alertGlow = Color(red: 0.65, green: 0.12, blue: 0.14)

    // 各卡片强调色
    static let cpuAccent = Color(red: 0.22, green: 0.85, blue: 0.62)
    static let cpuGlow = Color(red: 0.11, green: 0.45, blue: 0.34)

    static let memAccent = Color(red: 0.93, green: 0.38, blue: 0.36)
    static let memGlow = Color(red: 0.52, green: 0.15, blue: 0.16)

    static let storageBorder = Color.white.opacity(0.22)
    static let storageGlow = Color(red: 0.25, green: 0.22, blue: 0.20)

    static let thermalAccent = Color(red: 0.92, green: 0.64, blue: 0.20)
    static let thermalGlow = Color(red: 0.46, green: 0.31, blue: 0.09)
    static let thermalSubtleGreen = Color(red: 0.16, green: 0.26, blue: 0.15)

    static let batteryAccent = Color(red: 0.52, green: 0.86, blue: 0.32)
    static let batteryGlow = Color(red: 0.18, green: 0.36, blue: 0.16)

    static let networkAccent = Color(red: 0.36, green: 0.62, blue: 0.96)
    static let networkGlow = Color(red: 0.14, green: 0.25, blue: 0.48)

    // 语义分类色（存储 & 内存分段）
    static let segGreen = Color(red: 0.34, green: 0.82, blue: 0.44)
    static let segOrange = Color(red: 0.94, green: 0.52, blue: 0.26)
    static let segBlue = Color(red: 0.28, green: 0.62, blue: 0.96)
    static let segYellow = Color(red: 0.95, green: 0.78, blue: 0.25)
    static let segRed = Color(red: 0.90, green: 0.32, blue: 0.32)
    static let segTeal = Color(red: 0.22, green: 0.72, blue: 0.76)
    static let segFree = Color.white.opacity(0.22)
}

/// 统一的 Bento 卡片容器：深色底 + 顶部微光渐变 + 顶部高光细边 + Hover 提亮 + 告警高亮态。
struct BentoCard<Content: View>: View {
    let borderColor: Color
    let topGlow: Color
    var bottomGlow: Color = .clear
    var isAlert: Bool = false
    var isHovered: Bool = false
    @ViewBuilder let content: () -> Content

    private var effectiveBorder: Color {
        isAlert ? PanelPalette.alertAccent : borderColor
    }

    private var effectiveTopGlow: Color {
        isAlert ? PanelPalette.alertGlow : topGlow
    }

    private var borderOpacity: Double {
        if isAlert { return isHovered ? 0.95 : 0.80 }
        return isHovered ? 0.88 : 0.55
    }

    private var glowOpacity: Double {
        if isAlert { return isHovered ? 0.72 : 0.58 }
        return isHovered ? 0.68 : 0.52
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                shape
                    .fill(PanelPalette.cardBackground)
                    .overlay {
                        LinearGradient(
                            colors: [
                                effectiveTopGlow.opacity(glowOpacity),
                                Color.clear,
                                bottomGlow.opacity(isHovered ? 0.38 : 0.30),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(shape)
                    }
                    // 顶部 1pt 玻璃反光边，提升卡片的立体层次感。
                    .overlay {
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.22 : 0.12),
                                        Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 0.75
                            )
                    }
            }
            .overlay {
                shape
                    .strokeBorder(effectiveBorder.opacity(borderOpacity), lineWidth: isAlert ? 1.2 : 1)
            }
            .clipShape(shape)
            .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

/// 卡片告警状态指示灯：平时隐藏，超出阈值时在标题旁亮起柔光红点（用双层同心圆替代 `.shadow` 避免离屏阴影开销）。
struct AlertPulseDot: View {
    var color: Color = PanelPalette.alertAccent

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: 9, height: 9)
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
        .frame(width: 5, height: 5)
    }
}

/// 卡片 Hover 时的磨砂暗色详情浮层，展示精简掉的进程/明细而不破坏静息态排版。
struct CardHoverOverlay<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelPalette.overlayBackground.opacity(0.93))
                .overlay {
                    LinearGradient(
                        colors: [accent.opacity(0.16), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
        }
    }
}

/// 卡片顶部的细进度条（CPU / MEM 共用）。
struct ThinMetricBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PanelPalette.trackBackground)
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * clamped))
            }
        }
        .frame(height: 3)
    }
}
