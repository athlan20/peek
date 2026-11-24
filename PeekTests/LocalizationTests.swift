import XCTest
@testable import Peek

/// 校验多语言切换状态与 en / zh-Hans 关键文案解析。
final class LocalizationTests: XCTestCase {
    private var appBundle: Bundle { Bundle(for: SystemMonitor.self) }
    private let enLocale = Locale(identifier: "en")
    private let zhLocale = Locale(identifier: "zh-Hans")

    @MainActor
    func testLanguageManagerSwitchesAndPersists() throws {
        let suiteName = "cc.yuntianyou.peek.tests.lang-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let manager = LanguageManager(store: store)
        XCTAssertEqual(manager.language, .system)

        manager.setLanguage(.zhHans)
        XCTAssertEqual(manager.language, .zhHans)
        XCTAssertEqual(manager.locale.identifier, "zh-Hans")
        XCTAssertEqual(store.appLanguage, .zhHans)

        manager.setLanguage(.en)
        XCTAssertEqual(manager.language, .en)
        XCTAssertEqual(manager.locale.identifier, "en")
        XCTAssertEqual(store.appLanguage, .en)
    }

    func testAppLanguageDisplayTitlesUseAutonyms() {
        XCTAssertEqual(AppLanguage.en.displayTitle(locale: zhLocale, bundle: appBundle), "English")
        XCTAssertEqual(AppLanguage.zhHans.displayTitle(locale: enLocale, bundle: appBundle), "简体中文")
        XCTAssertEqual(AppLanguage.system.displayTitle(locale: enLocale, bundle: appBundle), "System")
        XCTAssertEqual(AppLanguage.system.displayTitle(locale: zhLocale, bundle: appBundle), "跟随系统")
    }

    func testBentoPanelAndSettingsTranslationsResolve() {
        let samples: [(String.LocalizationValue, String, String)] = [
            ("MEM", "MEM", "内存"),
            ("STORAGE", "STORAGE", "存储"),
            ("NETWORK", "NETWORK", "网络"),
            ("BATTERY", "BATTERY", "电池"),
            ("TEMPERATURE", "TEMPERATURE", "温度"),
            ("GENERAL", "GENERAL", "通用"),
            ("Language", "Language", "界面语言"),
            ("UPDATES", "UPDATES", "软件更新"),
            ("Fanless", "Fanless", "无风扇"),
            ("No active dev ports", "No active dev ports", "暂无活跃开发端口"),
            ("HOT", "HOT", "过热"),
            ("COOL", "COOL", "凉爽"),
            ("Full Disk Access Recommended", "Full Disk Access Recommended", "建议授予完全磁盘访问权限"),
            ("Continue Without Access", "Continue Without Access", "暂不授权，继续扫描"),
            ("Menu bar", "Menu bar", "菜单栏显示"),
            ("settings.menubar.memory", "Mem", "内存"),
            ("settings.menubar.network", "Net", "网络"),
        ]

        for (key, expectedEn, expectedZh) in samples {
            XCTAssertEqual(L10n.text(key, locale: enLocale, bundle: appBundle), expectedEn)
            XCTAssertEqual(L10n.text(key, locale: zhLocale, bundle: appBundle), expectedZh)
        }
    }

    func testPanelFormatRespectsExplicitLocale() {
        let fanless = ThermalStats(
            temperatureCelsius: 42,
            gpuTemperatureCelsius: nil,
            ssdTemperatureCelsius: nil,
            fanRPM: nil,
            fanCount: 0
        )
        XCTAssertEqual(PanelFormat.fanRPM(fanless, locale: enLocale, bundle: appBundle), "Fanless")
        XCTAssertEqual(PanelFormat.fanRPM(fanless, locale: zhLocale, bundle: appBundle), "无风扇")
    }
}
