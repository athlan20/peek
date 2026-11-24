import XCTest
@testable import Peek

/// Analyze 扫描结果缓存：读写、上限、删除后同步、坏文件和旧版本。
final class AnalyzeCacheTests: XCTestCase {
    private var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-analyze-cache-\(UUID().uuidString)")
            .appendingPathComponent("analyze-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func item(_ path: String, _ size: UInt64, directory: Bool = true) -> AnalyzeItem {
        AnalyzeItem(
            url: URL(fileURLWithPath: path, isDirectory: directory),
            name: (path as NSString).lastPathComponent,
            isDirectory: directory, size: size, isInaccessible: false)
    }

    func testRoundTrip() {
        var cache = AnalyzeCache()
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let listing = AnalyzeCache.Listing(
            items: [item("/Users/tester/work", 300), item("/Users/tester/a.zip", 50, directory: false)],
            totalBytes: 350, rootInaccessible: false, scannedAt: Date(timeIntervalSince1970: 1_000))
        cache.store(listing, for: home)
        cache.agents = AnalyzeCache.Agents(
            agents: [AnalyzeItem(
                url: URL(string: "peek-agent://claude")!, name: "Claude Code",
                isDirectory: true, size: 10, isInaccessible: false)],
            paths: ["claude": [item("/Users/tester/.claude", 10)]],
            scannedAt: Date(timeIntervalSince1970: 2_000))
        cache.save(to: file)

        let loaded = AnalyzeCache.load(from: file)
        XCTAssertEqual(loaded.listing(for: home), listing)
        // 路径末尾有没有斜杠都是同一层。
        XCTAssertEqual(loaded.listing(for: URL(fileURLWithPath: "/Users/tester")), listing)
        XCTAssertEqual(loaded.agents, cache.agents)
        XCTAssertNil(loaded.downloads)
    }

    func testMissingCorruptOrOldVersionIsEmpty() throws {
        XCTAssertTrue(AnalyzeCache.load(from: file).listings.isEmpty)

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(AnalyzeCache.load(from: file).listings.isEmpty)

        var old = AnalyzeCache()
        old.version = AnalyzeCache.currentVersion + 1
        old.store(
            AnalyzeCache.Listing(items: [], totalBytes: 0, rootInaccessible: false, scannedAt: Date()),
            for: URL(fileURLWithPath: "/tmp"))
        old.save(to: file)
        XCTAssertTrue(AnalyzeCache.load(from: file).listings.isEmpty)
    }

    func testLimits() {
        var cache = AnalyzeCache()
        for index in 0..<(AnalyzeCache.maxListings + 5) {
            cache.store(
                AnalyzeCache.Listing(
                    items: [], totalBytes: 0, rootInaccessible: false,
                    scannedAt: Date(timeIntervalSince1970: TimeInterval(index))),
                for: URL(fileURLWithPath: "/d/\(index)"))
        }
        XCTAssertEqual(cache.listings.count, AnalyzeCache.maxListings)
        // 丢掉的是最早扫的。
        XCTAssertNil(cache.listing(for: URL(fileURLWithPath: "/d/0")))
        XCTAssertNotNil(cache.listing(for: URL(fileURLWithPath: "/d/\(AnalyzeCache.maxListings + 4)")))

        let huge = (0...AnalyzeCache.maxItemsPerListing).map { item("/big/\($0)", 1, directory: false) }
        cache.store(
            AnalyzeCache.Listing(items: huge, totalBytes: 0, rootInaccessible: false, scannedAt: Date()),
            for: URL(fileURLWithPath: "/big"))
        XCTAssertNil(cache.listing(for: URL(fileURLWithPath: "/big")))
    }

    func testForgetUpdatesAncestorsAndDropsDescendants() {
        var cache = AnalyzeCache()
        let date = Date()
        cache.store(
            AnalyzeCache.Listing(
                items: [item("/u/work", 1_000), item("/u/Music", 200)],
                totalBytes: 1_200, rootInaccessible: false, scannedAt: date),
            for: URL(fileURLWithPath: "/u"))
        cache.store(
            AnalyzeCache.Listing(
                items: [item("/u/work/peek", 700), item("/u/work/other", 300)],
                totalBytes: 1_000, rootInaccessible: false, scannedAt: date),
            for: URL(fileURLWithPath: "/u/work"))
        cache.store(
            AnalyzeCache.Listing(
                items: [item("/u/work/peek/node_modules", 600)],
                totalBytes: 700, rootInaccessible: false, scannedAt: date),
            for: URL(fileURLWithPath: "/u/work/peek"))
        cache.store(
            AnalyzeCache.Listing(
                items: [item("/u/work/peek/node_modules/x", 600)],
                totalBytes: 600, rootInaccessible: false, scannedAt: date),
            for: URL(fileURLWithPath: "/u/work/peek/node_modules"))

        cache.forget(item("/u/work/peek/node_modules", 600))

        XCTAssertNil(cache.listing(for: URL(fileURLWithPath: "/u/work/peek/node_modules")))
        let peek = cache.listing(for: URL(fileURLWithPath: "/u/work/peek"))
        XCTAssertEqual(peek?.items.count, 0)
        XCTAssertEqual(peek?.totalBytes, 100)
        let work = cache.listing(for: URL(fileURLWithPath: "/u/work"))
        XCTAssertEqual(work?.items.first { $0.name == "peek" }?.size, 100)
        XCTAssertEqual(work?.totalBytes, 400)
        let root = cache.listing(for: URL(fileURLWithPath: "/u"))
        XCTAssertEqual(root?.items.first { $0.name == "work" }?.size, 400)
        XCTAssertEqual(root?.items.first { $0.name == "Music" }?.size, 200)
        XCTAssertEqual(root?.totalBytes, 600)
    }

    func testCheckpointForgetsTrashedItem() {
        var checkpoint = AnalyzeScanCheckpoint(
            finished: [item("/u/a", 500), item("/u/b", 100)],
            frames: [
                .init(path: "/u/c", doneNames: ["x", "y"], doneBytes: 300),
                .init(path: "/u/c/z", doneNames: ["k"], doneBytes: 40),
            ],
            scannedBytes: 940, itemCount: 10)
        // 扫完的第一层子项里的东西:那一项缩小。
        checkpoint.forget(item("/u/a/inner", 200))
        XCTAssertEqual(checkpoint.finished.first { $0.name == "a" }?.size, 300)
        // 正在扫的那一层里已经量完的子项:合计减掉,名字去掉(接着扫时也不会再量它,它已经不在了)。
        checkpoint.forget(item("/u/c/x", 120))
        XCTAssertEqual(checkpoint.frames[0].doneBytes, 180)
        XCTAssertEqual(checkpoint.frames[0].doneNames, ["y"])
        // 还没量到的:不动。
        checkpoint.forget(item("/u/c/z/notyet", 10))
        XCTAssertEqual(checkpoint.frames[1].doneBytes, 40)
        // 第一层整项删掉。
        checkpoint.forget(item("/u/b", 100))
        XCTAssertNil(checkpoint.finished.first { $0.name == "b" })
    }

    @MainActor
    func testFullDiskAccessGateBlocksAutoScanUntilAuthorizedOrSkipped() {
        final class Flag: @unchecked Sendable { var granted = false }
        let flag = Flag()

        let model = AnalyzeModel(cacheURL: file, probeFullDiskAccess: { flag.granted })
        model.start()
        defer { model.stop() }

        XCTAssertTrue(model.needsFullDiskAccessPrompt)
        XCTAssertTrue(model.stack.isEmpty)
        XCTAssertFalse(model.isScanning)
        XCTAssertFalse(model.isScanningDownloads)

        // 未授权时切到 Agent 页也不应偷跑扫描。
        model.tab = .agents
        XCTAssertTrue(model.stack.isEmpty)
        model.tab = .items

        // 模拟用户到系统设置授权后切回前台。
        flag.granted = true
        model.recheckFullDiskAccess()
        XCTAssertFalse(model.needsFullDiskAccessPrompt)
        XCTAssertFalse(model.stack.isEmpty)
    }

    @MainActor
    func testContinueWithoutFullDiskAccessStartsScan() {
        let model = AnalyzeModel(cacheURL: file, probeFullDiskAccess: { false })
        model.start()
        defer { model.stop() }

        XCTAssertTrue(model.needsFullDiskAccessPrompt)
        XCTAssertTrue(model.stack.isEmpty)

        model.continueWithoutFullDiskAccess()
        XCTAssertFalse(model.needsFullDiskAccessPrompt)
        XCTAssertFalse(model.stack.isEmpty)
    }
}
