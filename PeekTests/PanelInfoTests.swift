import XCTest

@testable import Peek

/// PEEK-17 面板信息行、趋势小图用到的纯计算：样本环形缓冲、运行时长格式、芯片名、网速归一化。
final class PanelInfoTests: XCTestCase {
    // MARK: - SampleHistory

    func testSampleHistoryNeverExceedsCapacity() {
        var history = SampleHistory(capacity: 3)
        for index in 0..<10 {
            history.append(Double(index))
        }
        XCTAssertEqual(history.values.count, 3)
        XCTAssertEqual(history.values, [7, 8, 9])
    }

    func testSampleHistoryDropsOldestAndKeepsOrder() {
        var history = SampleHistory(capacity: 4)
        history.append(1)
        history.append(2)
        XCTAssertEqual(history.values, [1, 2])
        history.append(3)
        history.append(4)
        history.append(5)
        XCTAssertEqual(history.values, [2, 3, 4, 5])
    }

    func testSampleHistoryInitKeepsNewestValues() {
        let history = SampleHistory(capacity: 3, values: [1, 2, 3, 4, 5])
        XCTAssertEqual(history.capacity, 3)
        XCTAssertEqual(history.values, [3, 4, 5])
        XCTAssertEqual(SampleHistory().capacity, SampleHistory.defaultCapacity)
        XCTAssertEqual(SampleHistory.defaultCapacity, 60)
    }

    // MARK: - 运行时长

    func testUptimeBuckets() {
        XCTAssertEqual(PanelFormat.uptime(59 * 60), .init(amount: 59, unit: .minutes))
        XCTAssertEqual(PanelFormat.uptime(3_600), .init(amount: 1, unit: .hours))
        XCTAssertEqual(PanelFormat.uptime(47 * 3_600), .init(amount: 47, unit: .hours))
        // 48 小时开始按天算，显示 2 天。
        XCTAssertEqual(PanelFormat.uptime(48 * 3_600), .init(amount: 2, unit: .days))
        XCTAssertEqual(PanelFormat.uptime(5 * 86_400), .init(amount: 5, unit: .days))
        XCTAssertEqual(PanelFormat.uptime(-10), .init(amount: 0, unit: .minutes))
    }

    func testUptimeTextIsLocalized() {
        // 英文是源语言，app 包里只为 zh-Hans 生成了 .lproj，所以英文用测试包（没有本地化资源）
        // 查一遍：查不到时返回的就是插值后的 key，也就是英文原文。中文用 app 包查。
        let sourceBundle = Bundle(for: PanelInfoTests.self)
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(
            PanelFormat.uptimeText(59 * 60, locale: .current, bundle: sourceBundle), "Up 59m")
        XCTAssertEqual(
            PanelFormat.uptimeText(13 * 3_600, locale: .current, bundle: sourceBundle), "Up 13h")
        XCTAssertEqual(
            PanelFormat.uptimeText(3_600, locale: chinese, bundle: .main), "已运行 1 小时")
        XCTAssertEqual(
            PanelFormat.uptimeText(5 * 86_400, locale: chinese, bundle: .main), "已运行 5 天")
    }

    // MARK: - 芯片名

    func testChipNameStripsApplePrefix() {
        XCTAssertEqual(SystemInfo.chipName(fromBrandString: "Apple M5 Pro"), "M5 Pro")
        XCTAssertEqual(SystemInfo.chipName(fromBrandString: "Apple M3 Max"), "M3 Max")
        XCTAssertEqual(SystemInfo.chipName(fromBrandString: " Apple  M2 \n"), "M2")
        // 不是 Apple 芯片就照原样显示。
        XCTAssertEqual(
            SystemInfo.chipName(fromBrandString: "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"),
            "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz")
        XCTAssertNil(SystemInfo.chipName(fromBrandString: nil))
        XCTAssertNil(SystemInfo.chipName(fromBrandString: "   "))
    }

    func testOSVersionText() {
        XCTAssertEqual(
            SystemInfo.osVersionText(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)),
            "27.0")
    }

    // MARK: - 网速归一化

    func testNetworkHistoryNormalizesToHistoryPeak() {
        let values = PanelFormat.normalizedRate([200_000, 400_000, 0])
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(values[1], 1, accuracy: 0.0001)
        XCTAssertEqual(values[2], 0, accuracy: 0.0001)
    }

    func testNetworkHistoryUsesMinimumScaleForSmallValues() {
        // 最大只有 50 KB/s，分母仍取 100 KB/s，噪声不会被放大成满格。
        let values = PanelFormat.normalizedRate([10_000, 50_000])
        XCTAssertEqual(values[0], 0.1, accuracy: 0.0001)
        XCTAssertEqual(values[1], 0.5, accuracy: 0.0001)
        XCTAssertTrue(PanelFormat.normalizedRate([]).isEmpty)
    }

    // MARK: - 下载/上传共用分母

    func testNormalizedRatesShareOneDenominator() {
        // 上行峰值 200 KB/s 决定分母，下行按同一个分母算，两条线能直接比较。
        let (down, up) = PanelFormat.normalizedRates([50_000, 100_000], [200_000, 0])
        XCTAssertEqual(down[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(down[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(up[0], 1, accuracy: 0.0001)
        XCTAssertEqual(up[1], 0, accuracy: 0.0001)
    }

    func testNormalizedRatesUseMinimumScaleForSmallValues() {
        // 两条都只有几十 KB/s，分母仍取 100 KB/s。
        let (down, up) = PanelFormat.normalizedRates([25_000], [50_000])
        XCTAssertEqual(down[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(up[0], 0.5, accuracy: 0.0001)
    }

    func testNormalizedRatesWithEmptyArrays() {
        let (down, up) = PanelFormat.normalizedRates([], [])
        XCTAssertTrue(down.isEmpty)
        XCTAssertTrue(up.isEmpty)
        // 只有一条有数据时，另一条返回空数组，分母仍按有数据那条算。
        let (onlyDown, noUp) = PanelFormat.normalizedRates([300_000], [])
        XCTAssertEqual(onlyDown[0], 1, accuracy: 0.0001)
        XCTAssertTrue(noUp.isEmpty)
    }

    func testNormalizedRatesKeepOwnLengths() {
        let (down, up) = PanelFormat.normalizedRates(
            [150_000, 300_000, 0], [300_000, 150_000])
        XCTAssertEqual(down.count, 3)
        XCTAssertEqual(up.count, 2)
        XCTAssertEqual(down.map { ($0 * 10_000).rounded() / 10_000 }, [0.5, 1, 0])
        XCTAssertEqual(up.map { ($0 * 10_000).rounded() / 10_000 }, [1, 0.5])
    }
}