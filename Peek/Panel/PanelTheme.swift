import AppKit
import SwiftUI

/// 面板与独立窗口的 Bento 视觉色板，同时支持深色与浅色（Porcelain Mist Bento）模式。
enum PanelPalette {
    /// 按当前 AppKit / SwiftUI 外观动态解析颜色。
    static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }

    static func dynamicHex(
        dark: UInt32, darkAlpha: CGFloat = 1,
        light: UInt32, lightAlpha: CGFloat = 1
    ) -> Color {
        dynamic(
            dark: nsColor(hex: dark, alpha: darkAlpha),
            light: nsColor(hex: light, alpha: lightAlpha)
        )
    }

    static func nsColor(hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    // MARK: - 画布、卡片与分割线

    static let panelBackground = dynamic(
        dark: NSColor(srgbRed: 0.075, green: 0.095, blue: 0.135, alpha: 1),
        light: nsColor(hex: 0xF1F4F9)
    )
    static let cardBackground = dynamic(
        dark: NSColor(srgbRed: 0.095, green: 0.118, blue: 0.165, alpha: 1),
        light: nsColor(hex: 0xFFFFFF)
    )
    static let overlayBackground = dynamic(
        dark: NSColor(srgbRed: 0.075, green: 0.095, blue: 0.140, alpha: 1),
        light: nsColor(hex: 0xFFFFFF)
    )
    static let inactivePixel = dynamic(
        dark: NSColor(srgbRed: 0.14, green: 0.19, blue: 0.27, alpha: 1),
        light: nsColor(hex: 0xDCE3EE)
    )
    static let trackBackground = dynamic(
        dark: NSColor.white.withAlphaComponent(0.08),
        light: nsColor(hex: 0x0F172A, alpha: 0.075)
    )
    static let divider = dynamic(
        dark: NSColor.white.withAlphaComponent(0.09),
        light: nsColor(hex: 0x0F172A, alpha: 0.085)
    )

    // MARK: - 控件与列表表面

    static let controlBackground = dynamic(
        dark: NSColor(srgbRed: 0.095, green: 0.118, blue: 0.165, alpha: 1),
        light: nsColor(hex: 0xFFFFFF)
    )
    static let controlHover = dynamic(
        dark: NSColor.white.withAlphaComponent(0.10),
        light: nsColor(hex: 0xF8FAFC)
    )
    static let controlBorder = dynamic(
        dark: NSColor.white.withAlphaComponent(0.10),
        light: nsColor(hex: 0x0F172A, alpha: 0.09)
    )
    static let controlBorderHover = dynamic(
        dark: NSColor.white.withAlphaComponent(0.22),
        light: nsColor(hex: 0x0F172A, alpha: 0.18)
    )
    static let pillBackground = dynamic(
        dark: NSColor.white.withAlphaComponent(0.04),
        light: nsColor(hex: 0x0F172A, alpha: 0.045)
    )
    static let pillHover = dynamic(
        dark: NSColor.white.withAlphaComponent(0.10),
        light: nsColor(hex: 0x0F172A, alpha: 0.085)
    )
    static let pillBorder = dynamic(
        dark: NSColor.white.withAlphaComponent(0.08),
        light: nsColor(hex: 0x0F172A, alpha: 0.08)
    )
    static let segmentedTrack = dynamic(
        dark: NSColor.black.withAlphaComponent(0.22),
        light: nsColor(hex: 0xE6ECF4)
    )
    static let segmentedActive = dynamic(
        dark: NSColor.white.withAlphaComponent(0.12),
        light: nsColor(hex: 0x0F172A, alpha: 0.08)
    )
    static let rowBackground = dynamic(
        dark: NSColor.white.withAlphaComponent(0.02),
        light: nsColor(hex: 0xFFFFFF, alpha: 0.72)
    )
    static let rowHover = dynamic(
        dark: NSColor.white.withAlphaComponent(0.06),
        light: nsColor(hex: 0x0F172A, alpha: 0.04)
    )
    static let rowSelected = dynamic(
        dark: NSColor.white.withAlphaComponent(0.05),
        light: nsColor(hex: 0x2563EB, alpha: 0.07)
    )
    static let legendBackground = dynamic(
        dark: NSColor.black.withAlphaComponent(0.16),
        light: nsColor(hex: 0x0F172A, alpha: 0.035)
    )
    static let cardShadow = dynamic(
        dark: NSColor.clear,
        light: nsColor(hex: 0x0F172A, alpha: 0.05)
    )

    // MARK: - 文字层级

    static let textPrimary = dynamic(
        dark: NSColor.white.withAlphaComponent(0.95),
        light: nsColor(hex: 0x0F172A, alpha: 0.94)
    )
    static let textSecondary = dynamic(
        dark: NSColor.white.withAlphaComponent(0.64),
        light: nsColor(hex: 0x334155, alpha: 0.80)
    )
    static let textMuted = dynamic(
        dark: NSColor.white.withAlphaComponent(0.45),
        light: nsColor(hex: 0x475569, alpha: 0.65)
    )

    // MARK: - 告警强调色

    static let alertAccent = dynamic(
        dark: NSColor(srgbRed: 0.98, green: 0.34, blue: 0.32, alpha: 1),
        light: nsColor(hex: 0xDC2626)
    )
    static let alertGlow = dynamic(
        dark: NSColor(srgbRed: 0.65, green: 0.12, blue: 0.14, alpha: 1),
        light: nsColor(hex: 0xEF4444)
    )

    // MARK: - 各卡片强调色

    static let cpuAccent = dynamic(
        dark: NSColor(srgbRed: 0.22, green: 0.85, blue: 0.62, alpha: 1),
        light: nsColor(hex: 0x0D9468)
    )
    static let cpuGlow = dynamic(
        dark: NSColor(srgbRed: 0.11, green: 0.45, blue: 0.34, alpha: 1),
        light: nsColor(hex: 0x10B981)
    )

    static let memAccent = dynamic(
        dark: NSColor(srgbRed: 0.93, green: 0.38, blue: 0.36, alpha: 1),
        light: nsColor(hex: 0xDC3545)
    )
    static let memGlow = dynamic(
        dark: NSColor(srgbRed: 0.52, green: 0.15, blue: 0.16, alpha: 1),
        light: nsColor(hex: 0xF43F5E)
    )

    static let storageBorder = dynamic(
        dark: NSColor.white.withAlphaComponent(0.22),
        light: nsColor(hex: 0x64748B, alpha: 0.55)
    )
    static let storageGlow = dynamic(
        dark: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.20, alpha: 1),
        light: nsColor(hex: 0x64748B)
    )

    static let thermalAccent = dynamic(
        dark: NSColor(srgbRed: 0.92, green: 0.64, blue: 0.20, alpha: 1),
        light: nsColor(hex: 0xC27803)
    )
    static let thermalGlow = dynamic(
        dark: NSColor(srgbRed: 0.46, green: 0.31, blue: 0.09, alpha: 1),
        light: nsColor(hex: 0xF59E0B)
    )
    static let thermalSubtleGreen = dynamic(
        dark: NSColor(srgbRed: 0.16, green: 0.26, blue: 0.15, alpha: 1),
        light: nsColor(hex: 0x10B981, alpha: 0.45)
    )

    static let batteryAccent = dynamic(
        dark: NSColor(srgbRed: 0.52, green: 0.86, blue: 0.32, alpha: 1),
        light: nsColor(hex: 0x3F9118)
    )
    static let batteryGlow = dynamic(
        dark: NSColor(srgbRed: 0.18, green: 0.36, blue: 0.16, alpha: 1),
        light: nsColor(hex: 0x65A30D)
    )

    static let networkAccent = dynamic(
        dark: NSColor(srgbRed: 0.36, green: 0.62, blue: 0.96, alpha: 1),
        light: nsColor(hex: 0x2563EB)
    )
    static let networkGlow = dynamic(
        dark: NSColor(srgbRed: 0.14, green: 0.25, blue: 0.48, alpha: 1),
        light: nsColor(hex: 0x3B82F6)
    )

    // MARK: - 语义分类色（存储 & 内存分段）

    static let segGreen = dynamic(
        dark: NSColor(srgbRed: 0.34, green: 0.82, blue: 0.44, alpha: 1),
        light: nsColor(hex: 0x22A04E)
    )
    static let segOrange = dynamic(
        dark: NSColor(srgbRed: 0.94, green: 0.52, blue: 0.26, alpha: 1),
        light: nsColor(hex: 0xE06319)
    )
    static let segBlue = dynamic(
        dark: NSColor(srgbRed: 0.28, green: 0.62, blue: 0.96, alpha: 1),
        light: nsColor(hex: 0x2563EB)
    )
    static let segYellow = dynamic(
        dark: NSColor(srgbRed: 0.95, green: 0.78, blue: 0.25, alpha: 1),
        light: nsColor(hex: 0xD99B08)
    )
    static let segRed = dynamic(
        dark: NSColor(srgbRed: 0.90, green: 0.32, blue: 0.32, alpha: 1),
        light: nsColor(hex: 0xDC2626)
    )
    static let segTeal = dynamic(
        dark: NSColor(srgbRed: 0.22, green: 0.72, blue: 0.76, alpha: 1),
        light: nsColor(hex: 0x0E949E)
    )
    static let segFree = dynamic(
        dark: NSColor.white.withAlphaComponent(0.22),
        light: nsColor(hex: 0xCBD5E1)
    )

    // MARK: - Treemap 公共色（方案 A：浅色柔彩浅底 + 深色文字）

    static let treemapTextPrimary = dynamic(
        dark: NSColor.white.withAlphaComponent(0.95),
        light: nsColor(hex: 0x0F172A, alpha: 0.94)
    )
    static let treemapTextSecondary = dynamic(
        dark: NSColor.white.withAlphaComponent(0.75),
        light: nsColor(hex: 0x0F172A, alpha: 0.64)
    )
    static let treemapTileBorder = dynamic(
        dark: NSColor.white.withAlphaComponent(0.15),
        light: nsColor(hex: 0x0F172A, alpha: 0.12)
    )
    static let treemapSelectionBorder = dynamic(
        dark: NSColor.white,
        light: nsColor(hex: 0x2563EB)
    )
    static let treemapOtherFill = dynamic(
        dark: NSColor(srgbRed: 0.14, green: 0.19, blue: 0.27, alpha: 1),
        light: nsColor(hex: 0xE1E7F0)
    )
}

/// 统一的 Bento 卡片容器：深/浅自适应底色 + 顶部微光渐变 + 顶部高光细边 + Hover 提亮 + 告警高亮态。
struct BentoCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let borderColor: Color
    let topGlow: Color
    var bottomGlow: Color = .clear
    var isAlert: Bool = false
    var isHovered: Bool = false
    @ViewBuilder let content: () -> Content

    private var isLight: Bool { colorScheme == .light }

    private var effectiveBorder: Color {
        isAlert ? PanelPalette.alertAccent : borderColor
    }

    private var effectiveTopGlow: Color {
        isAlert ? PanelPalette.alertGlow : topGlow
    }

    private var borderOpacity: Double {
        if isLight {
            if isAlert { return isHovered ? 0.85 : 0.60 }
            return isHovered ? 0.58 : 0.34
        }
        if isAlert { return isHovered ? 0.95 : 0.80 }
        return isHovered ? 0.88 : 0.55
    }

    private var glowOpacity: Double {
        if isLight {
            if isAlert { return isHovered ? 0.20 : 0.13 }
            return isHovered ? 0.18 : 0.11
        }
        if isAlert { return isHovered ? 0.72 : 0.58 }
        return isHovered ? 0.68 : 0.52
    }

    private var bottomGlowOpacity: Double {
        if isLight { return isHovered ? 0.10 : 0.06 }
        return isHovered ? 0.38 : 0.30
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
                                bottomGlow.opacity(bottomGlowOpacity),
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
                                        Color.white.opacity(isLight ? 0.90 : (isHovered ? 0.22 : 0.12)),
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
            .shadow(color: PanelPalette.cardShadow, radius: isLight ? 3 : 0, x: 0, y: isLight ? 1 : 0)
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

/// 卡片 Hover 时的磨砂详情浮层，展示精简掉的进程/明细而不破坏静息态排版。
struct CardHoverOverlay<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        let isLight = colorScheme == .light
        VStack(alignment: .leading, spacing: 5) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelPalette.overlayBackground.opacity(isLight ? 0.94 : 0.93))
                .overlay {
                    LinearGradient(
                        colors: [accent.opacity(isLight ? 0.08 : 0.16), Color.clear],
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
