import XCTest
@testable import Peek

/// 卸载逻辑测试：全部在临时目录里造数据，废纸篓换成临时目录，不碰真实文件。
final class UninstallTests: XCTestCase {
    var root: URL!
    var home: URL!
    var apps: URL!
    var fakeTrash: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("peek-un-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        apps = root.appendingPathComponent("Applications")
        fakeTrash = root.appendingPathComponent("trash")
        for d in [home!, apps!, fakeTrash!] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    // MARK: - 造数据

    @discardableResult
    func makeApp(_ name: String, bundleID: String, displayName: String? = nil) throws -> URL {
        let app = apps.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name]
        if let displayName { plist["CFBundleDisplayName"] = displayName }
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 4000).write(to: contents.appendingPathComponent("blob"))
        return app
    }

    func lib(_ path: String, isFile: Bool = false) throws {
        let url = home.appendingPathComponent("Library/\(path)")
        if isFile {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 2, count: 3000).write(to: url)
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 2, count: 3000).write(to: url.appendingPathComponent("f"))
        }
    }

    func context(running: Set<String>? = []) -> UninstallContext {
        var c = CleanContext(home: home)
        c.runningBundleIDs = running
        c.allowsToolQueries = false
        return UninstallContext(clean: c, applicationDirectories: [apps])
    }

    func find(_ bundleID: String, running: Set<String>? = []) throws -> (app: InstalledApp, items: [ResidualItem]) {
        let ctx = context(running: running)
        let list = AppCatalog.list(context: ctx)
        let app = try XCTUnwrap(list.first { $0.bundleID == bundleID })
        return (app, ResidualFinder.find(for: app, installed: list, context: ctx))
    }

    // MARK: - 列表与不可卸载

    func testListReadsNameAndBlocks() throws {
        try makeApp("Foo", bundleID: "com.foo.app", displayName: "Foo Pro")
        try makeApp("Safari", bundleID: "com.apple.Safari")
        try makeApp("Xcode", bundleID: "com.apple.dt.Xcode")
        try makeApp("Me", bundleID: "cc.yuntianyou.peek.dev")
        try makeApp("Jamf", bundleID: "com.jamf.connect")
        try makeApp("Run", bundleID: "com.run.app")
        let list = AppCatalog.list(context: context(running: ["com.run.app"]))
        func reason(_ id: String) -> UninstallBlockReason? { list.first { $0.bundleID == id }?.blocked }
        XCTAssertEqual(list.first { $0.bundleID == "com.foo.app" }?.name, "Foo Pro")
        XCTAssertNil(reason("com.foo.app"))
        XCTAssertEqual(reason("com.apple.Safari"), .appleApp)
        XCTAssertNil(reason("com.apple.dt.Xcode"))
        XCTAssertEqual(reason("cc.yuntianyou.peek.dev"), .peekItself)
        XCTAssertEqual(reason("com.jamf.connect"), .vendorManaged)
        XCTAssertEqual(reason("com.run.app"), .running)
    }

    // MARK: - 残留

    func testExactBundleIDMatchesAndCategories() throws {
        try makeApp("Foo", bundleID: "com.foo.app")
        try lib("Caches/com.foo.app")
        try lib("Preferences/com.foo.app.plist", isFile: true)
        try lib("Preferences/com.foo.app.extra.plist", isFile: true)
        try lib("Application Support/com.foo.app")
        try lib("Saved Application State/com.foo.app.savedState")
        try lib("LaunchAgents/com.foo.app.helper.plist", isFile: true)
        try lib("Group Containers/ABCDE12345.com.foo.app")
        try lib("Caches/com.foo.other")   // 不相关
        let found = try find("com.foo.app").items
        XCTAssertEqual(Set(found.map { $0.url.lastPathComponent }), [
            "com.foo.app", "com.foo.app.plist", "com.foo.app.extra.plist", "com.foo.app.savedState",
            "com.foo.app.helper.plist", "ABCDE12345.com.foo.app",
        ])
        XCTAssertEqual(found.filter { $0.category == .personalData }.count, 2)  // Application Support + Group Containers
        XCTAssertTrue(found.filter { $0.category == .personalData }.allSatisfy { !$0.defaultSelected })
        XCTAssertTrue(found.filter { $0.category != .personalData }.allSatisfy(\.defaultSelected))
    }

    func testSameFamilyProtection() throws {
        try makeApp("Foo", bundleID: "com.foo.app")
        try makeApp("FooPro", bundleID: "com.foo.app.pro")
        try lib("Preferences/com.foo.app.pro.plist", isFile: true)
        try lib("Preferences/com.foo.app.plist", isFile: true)
        let names = try find("com.foo.app").items.map { $0.url.path }
        XCTAssertEqual(names.map { ($0 as NSString).lastPathComponent }, ["com.foo.app.plist"], "\(names)")
    }

    func testNameMatchRestrictions() throws {
        try makeApp("Slack", bundleID: "com.tinyspeck.slack")
        try makeApp("Code", bundleID: "com.microsoft.code")
        try makeApp("Dup", bundleID: "com.d.one", displayName: "Notes")
        try makeApp("Dup2", bundleID: "com.d.two", displayName: "Notes")
        try lib("Application Support/Slack")
        try lib("Application Support/slackish")        // 不是完全相同
        try lib("Application Support/Code")            // 通用词
        try lib("Application Support/Notes")           // 两个 App 同名
        let slack = try find("com.tinyspeck.slack").items
        XCTAssertEqual(slack.map { $0.url.lastPathComponent }, ["Slack"])
        XCTAssertTrue(slack[0].matchedByName)
        XCTAssertEqual(slack[0].category, .personalData)
        XCTAssertTrue(try find("com.microsoft.code").items.isEmpty)
        XCTAssertTrue(try find("com.d.one").items.isEmpty)
    }

    func testProtectedPathsAreNeverResiduals() throws {
        try makeApp("Peeky", bundleID: "com.peeky.app")
        try lib("Application Support/Peek")      // 名字不等于 Peeky，不匹配；确认保护路径本身不会被列出
        let items = try find("com.peeky.app").items
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - 执行

    func executor(_ ctx: UninstallContext) -> UninstallExecutor {
        var e = UninstallExecutor(context: ctx)
        let trash = fakeTrash!
        e.trashHandler = { url in
            (try? FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))) != nil
        }
        return e
    }

    func testUninstallTrashesAppAndSelectedResiduals() throws {
        let appURL = try makeApp("Foo", bundleID: "com.foo.app")
        try lib("Caches/com.foo.app")
        try lib("Application Support/com.foo.app")
        let ctx = context()
        let (app, items) = try find("com.foo.app")
        let chosen = items.filter(\.defaultSelected)   // 个人数据不勾选
        let out = executor(ctx).uninstall(app, residuals: chosen)
        XCTAssertTrue(out.appRemoved)
        XCTAssertEqual(out.processed, 2)
        XCTAssertFalse(fm.fileExists(atPath: appURL.path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.foo.app").path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/com.foo.app").path))
    }

    func testRunningAppIsRefused() throws {
        let appURL = try makeApp("Foo", bundleID: "com.foo.app")
        try lib("Caches/com.foo.app")
        let (app, items) = try find("com.foo.app")
        let out = executor(context(running: ["com.foo.app"])).uninstall(app, residuals: items)
        XCTAssertFalse(out.appRemoved)
        XCTAssertEqual(out.appFailureReason, "running")
        XCTAssertTrue(fm.fileExists(atPath: appURL.path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.foo.app").path))
    }

    func testResidualsUntouchedWhenAppCannotBeRemoved() throws {
        try makeApp("Foo", bundleID: "com.foo.app")
        try lib("Caches/com.foo.app")
        let (app, items) = try find("com.foo.app")
        var e = UninstallExecutor(context: context())
        e.trashHandler = { _ in false }
        let out = e.uninstall(app, residuals: items)
        XCTAssertFalse(out.appRemoved)
        XCTAssertEqual(out.appFailureReason, "cannotRemoveApp")
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.foo.app").path))
    }

    func testChangedResidualIsSkipped() throws {
        try makeApp("Foo", bundleID: "com.foo.app")
        try lib("Caches/com.foo.app")
        let (app, items) = try find("com.foo.app")
        let target = home.appendingPathComponent("Library/Caches/com.foo.app")
        try fm.removeItem(at: target)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let out = executor(context()).uninstall(app, residuals: items)
        XCTAssertTrue(out.appRemoved)
        XCTAssertEqual(out.skipped.first?.reason, .changed)
        XCTAssertTrue(fm.fileExists(atPath: target.path))
    }

    func testWhitelistedResidualIsSkipped() throws {
        try makeApp("Foo", bundleID: "com.foo.app")
        try lib("Caches/com.foo.app")
        var ctx = context()
        let (app, items) = try find("com.foo.app")
        ctx.clean.whitelist = [home.appendingPathComponent("Library/Caches/com.foo.app").path]
        let out = executor(ctx).uninstall(app, residuals: items)
        XCTAssertEqual(out.skipped.first?.reason, .whitelisted)
    }
}
