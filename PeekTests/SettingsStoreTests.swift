import XCTest
@testable import Peek

/// `SettingsStore` 的读写测试。全部用临时 suite，不碰真实用户设置。
final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUpWithError() throws {
        suiteName = "cc.yuntianyou.peek.tests.settings-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = SettingsStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
    }

    // MARK: - 白名单

    func testAddWhitelistNormalizesAndDedupes() {
        store.addToWhitelist(["/a//b/", "/a/b", "relative/path", "/a/../b", "/c/d"])
        XCTAssertEqual(store.whitelist, ["/a/b", "/c/d"])
    }

    func testAddWhitelistKeepsExistingEntries() {
        store.addToWhitelist(["/one"])
        store.addToWhitelist(["/one", "/two"])
        XCTAssertEqual(store.whitelist, ["/one", "/two"])
    }

    func testRemoveFromWhitelist() {
        store.addToWhitelist(["/one", "/two", "/three"])
        store.removeFromWhitelist("/two")
        XCTAssertEqual(store.whitelist, ["/one", "/three"])
    }

    func testWhitelistReadNormalizesStoredValues() {
        defaults.set(["/x//y/", "/x/y", "/z/../w"], forKey: SettingsStore.whitelistKey)
        XCTAssertEqual(store.whitelist, ["/x/y"])
    }

    // MARK: - 项目扫描目录

    func testProjectRootsNormalizeAndDedupe() {
        store.addProjectRoots(["/work//a/", "/work/a", "no-slash", "/work/b"])
        XCTAssertEqual(store.projectRoots, ["/work/a", "/work/b"])
        store.removeProjectRoot("/work/a")
        XCTAssertEqual(store.projectRoots, ["/work/b"])
    }

    func testProjectRootsEmptyByDefault() {
        XCTAssertTrue(store.projectRoots.isEmpty)
    }

    // MARK: - 刷新间隔

    func testRefreshIntervalDefaultsToOneSecond() {
        XCTAssertEqual(store.refreshInterval, 1)
        XCTAssertEqual(SettingsStore.refreshInterval(from: defaults), 1)
    }

    func testRefreshIntervalKeepsValidValues() {
        for seconds in SettingsStore.refreshIntervalOptions {
            store.refreshInterval = seconds
            XCTAssertEqual(defaults.integer(forKey: SettingsStore.refreshIntervalKey), seconds)
            XCTAssertEqual(store.refreshInterval, seconds)
        }
    }

    func testRefreshIntervalFallsBackForInvalidStoredValues() {
        for value in [0, 3, 10, -1, 100] {
            defaults.set(value, forKey: SettingsStore.refreshIntervalKey)
            XCTAssertEqual(store.refreshInterval, 1, "stored \(value) should fall back to 1")
        }
        defaults.set("abc", forKey: SettingsStore.refreshIntervalKey)
        XCTAssertEqual(store.refreshInterval, 1)
    }

    func testRefreshIntervalWriteClampsInvalidValues() {
        store.refreshInterval = 7
        XCTAssertEqual(store.refreshInterval, 1)
        XCTAssertEqual(defaults.integer(forKey: SettingsStore.refreshIntervalKey), 1)
    }

    // MARK: - 界面语言

    func testAppLanguageDefaultsToSystem() {
        XCTAssertEqual(store.appLanguage, .system)
        XCTAssertEqual(SettingsStore.appLanguage(from: defaults), .system)
    }

    func testAppLanguagePersistsValidValues() {
        for language in AppLanguage.allCases {
            store.appLanguage = language
            XCTAssertEqual(defaults.string(forKey: SettingsStore.appLanguageKey), language.rawValue)
            XCTAssertEqual(store.appLanguage, language)
        }
    }

    func testAppLanguageFallsBackToSystemForInvalidStoredValue() {
        defaults.set("fr-FR", forKey: SettingsStore.appLanguageKey)
        XCTAssertEqual(store.appLanguage, .system)
    }

    // MARK: - 界面外观

    func testAppAppearanceDefaultsToSystem() {
        XCTAssertEqual(store.appAppearance, .system)
        XCTAssertEqual(SettingsStore.appAppearance(from: defaults), .system)
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testAppAppearancePersistsValidValues() {
        for appearance in AppAppearance.allCases {
            store.appAppearance = appearance
            XCTAssertEqual(defaults.string(forKey: SettingsStore.appAppearanceKey), appearance.rawValue)
            XCTAssertEqual(store.appAppearance, appearance)
        }
    }

    func testAppAppearanceFallsBackToSystemForInvalidStoredValue() {
        defaults.set("sepia", forKey: SettingsStore.appAppearanceKey)
        XCTAssertEqual(store.appAppearance, .system)
    }

    // MARK: - 菜单栏显示指标

    func testMenuBarMetricDefaultsToCPU() {
        XCTAssertEqual(store.menuBarMetric, .cpu)
        XCTAssertEqual(SettingsStore.menuBarMetric(from: defaults), .cpu)
    }

    func testMenuBarMetricPersistsValidValues() {
        for metric in MenuBarMetric.allCases {
            store.menuBarMetric = metric
            XCTAssertEqual(defaults.string(forKey: SettingsStore.menuBarMetricKey), metric.rawValue)
            XCTAssertEqual(store.menuBarMetric, metric)
        }
    }

    func testMenuBarMetricFallsBackToCPUForInvalidStoredValue() {
        defaults.set("health", forKey: SettingsStore.menuBarMetricKey)
        XCTAssertEqual(store.menuBarMetric, .cpu)
    }

    func testMenuBarMetricFormatting() {
        let snap = SystemSnapshot.sample
        XCTAssertEqual(MenuBarMetric.cpu.formattedText(for: snap), PanelFormat.percent(snap.cpu.total))
        XCTAssertEqual(MenuBarMetric.memory.formattedText(for: snap), PanelFormat.percent(snap.memory.usedFraction))
        XCTAssertEqual(
            MenuBarMetric.temperature.formattedText(for: snap),
            PanelFormat.temperature(snap.thermal.temperatureCelsius))
        XCTAssertNil(MenuBarMetric.none.formattedText(for: snap))

        XCTAssertEqual(MenuBarMetric.compactRate(0), "0K")
        XCTAssertEqual(MenuBarMetric.compactRate(240_000), "240K")
        XCTAssertEqual(MenuBarMetric.compactRate(999_600), "1M")
        XCTAssertEqual(MenuBarMetric.compactRate(1_250_000), "1.3M")
        XCTAssertEqual(MenuBarMetric.compactRate(12_400_000), "12M")
        XCTAssertEqual(MenuBarMetric.compactRate(2_000_000_000), "2G")
        XCTAssertEqual(MenuBarMetric.compactRate(12_600_000_000), "13G")
    }
}