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
}