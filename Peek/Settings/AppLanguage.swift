import Foundation
import Observation

/// 应用界面语言选项。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// 跟随 macOS 系统语言（默认）。
    case system
    /// English
    case en
    /// 简体中文
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    /// 供 SwiftUI `.environment(\.locale, ...)` 与 `String(localized:locale:)` 使用。
    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .en: Locale(identifier: "en")
        case .zhHans: Locale(identifier: "zh-Hans")
        }
    }

    /// 选项标签：`English` 和 `简体中文` 始终用该语言自称，避免用户误切后认不出入口。
    func displayTitle(locale: Locale? = nil, bundle: Bundle = .main) -> String {
        switch self {
        case .system:
            let resolvedLocale = locale ?? L10n.currentLocale()
            let resolvedBundle = L10n.localizedBundle(for: resolvedLocale, in: bundle)
            return String(
                localized: "settings.language.system",
                defaultValue: "System",
                bundle: resolvedBundle,
                locale: resolvedLocale
            )
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }
}

/// 统一的命令式本地化取词入口，按当前用户选择的语言解析 `Localizable.xcstrings`。
enum L10n {
    /// 读取当前生效的 `Locale`（线程安全，可供非主线程的 `LocalizedError` 等调用）。
    nonisolated static func currentLocale(defaults: UserDefaults = .standard) -> Locale {
        SettingsStore.appLanguage(from: defaults).locale
    }

    /// 根据目标语言定位对应的 `.lproj` 子包。
    /// `String(localized:bundle:locale:)` 里的 `locale` 仅控制数字/日期插值格式，不切换 `.lproj` 词表；
    /// 因此显式指定 `en` / `zh-Hans` 时必须传对应的 `.lproj` 子包，才能在任意系统语言下准确取词。
    nonisolated static func localizedBundle(
        for locale: Locale?, in baseBundle: Bundle = .main
    ) -> Bundle {
        guard let locale else { return baseBundle }
        let id = locale.identifier
        if id.isEmpty || locale == .autoupdatingCurrent {
            return baseBundle
        }
        let candidates: [String] = if id.hasPrefix("zh") {
            ["zh-Hans", "zh"]
        } else if id.hasPrefix("en") {
            ["en", "Base"]
        } else {
            [id]
        }
        for name in candidates {
            if let path = baseBundle.path(forResource: name, ofType: "lproj"),
               let subBundle = Bundle(path: path)
            {
                return subBundle
            }
        }
        return baseBundle
    }

    nonisolated static func text(
        _ key: String.LocalizationValue,
        locale: Locale? = nil,
        bundle: Bundle = .main
    ) -> String {
        let resolvedLocale = locale ?? currentLocale()
        let resolvedBundle = localizedBundle(for: resolvedLocale, in: bundle)
        return String(localized: key, bundle: resolvedBundle, locale: resolvedLocale)
    }
}

/// 全局语言状态：负责驱动 SwiftUI 视图热切换（无需重启）以及同步非视图层文案语言。
@MainActor
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    private let store: SettingsStore

    private(set) var language: AppLanguage

    var locale: Locale { language.locale }

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.language = store.appLanguage
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        store.appLanguage = newLanguage
        language = store.appLanguage
    }
}
