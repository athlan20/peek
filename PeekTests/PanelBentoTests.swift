import AppKit
import SwiftUI
import XCTest

@testable import Peek

@MainActor
final class PanelBentoTests: XCTestCase {
    func testSMCKeyDataLayoutMatchesKernelABI() {
        XCTAssertEqual(MemoryLayout<SMCKeyData>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.stride, 80)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.key), 0)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.keyInfo), 28)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.result), 40)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.data8), 42)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.data32), 44)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.bytes), 48)
    }

    func testMemoryRatioFormatting() {
        let used = UInt64(10.8 * 1_073_741_824)
        let total = UInt64(16) << 30
        XCTAssertEqual(PanelFormat.memoryRatio(used: used, total: total), "10.8 GB / 16 GB")
    }

    func testCompactStorageFormatting() {
        XCTAssertEqual(PanelFormat.compactStorage(256_000_000_000), "256GB")
        XCTAssertEqual(PanelFormat.compactStorage(512_000_000_000), "512GB")
        XCTAssertEqual(PanelFormat.compactStorage(1_000_000_000_000), "1TB")
        XCTAssertEqual(PanelFormat.compactStorage(1_250_000_000_000), "1.3TB")
    }

    func testThermalFormatting() {
        XCTAssertEqual(PanelFormat.temperature(43.2), "43°C")
        XCTAssertEqual(PanelFormat.temperature(nil), "--°C")

        let activeFan = ThermalStats(temperatureCelsius: 43, fanRPM: 1200, fanCount: 1)
        XCTAssertEqual(PanelFormat.fanRPM(activeFan), "1200 RPM")

        let fanless = ThermalStats(temperatureCelsius: 40, fanRPM: nil, fanCount: 0)
        XCTAssertEqual(PanelFormat.fanRPM(fanless), "Fanless")

        let unknownFan = ThermalStats(temperatureCelsius: 40, fanRPM: nil, fanCount: 2)
        XCTAssertEqual(PanelFormat.fanRPM(unknownFan), "-- RPM")
    }

    func testPowerFormattingAndSamplerSmoke() {
        XCTAssertEqual(BatteryCard.formatWatts(nil), "-- W")
        XCTAssertEqual(BatteryCard.formatWatts(18.42), "18.4 W")
        XCTAssertEqual(BatteryCard.formatCompactWatts(26.24), "26.2W")
        XCTAssertEqual(BatteryCard.formatCompactWatts(108.6), "109W")

        let power = PowerSampler().sample()
        if let watts = power.systemWatts {
            XCTAssertGreaterThan(watts, 0)
            XCTAssertLessThan(watts, 500)
        }
    }

    func testBatteryTimeRemainingFormatting() {
        XCTAssertNil(PanelFormat.batteryTimeRemaining(nil))
        XCTAssertNil(PanelFormat.batteryTimeRemaining(0))
        XCTAssertEqual(PanelFormat.batteryTimeRemaining(45), "45m")
        XCTAssertEqual(PanelFormat.batteryTimeRemaining(90), "1h 30m")
        XCTAssertEqual(PanelFormat.batteryTimeRemaining(21 * 60), "21h")
    }

    func testTopMemoryProcessesSortsByMemoryDescending() {
        let procs = [
            ProcessUsage(pid: 1, name: "A", cpu: 0.9, memoryBytes: 100),
            ProcessUsage(pid: 2, name: "B", cpu: 0.1, memoryBytes: 500),
            ProcessUsage(pid: 3, name: "C", cpu: 0.2, memoryBytes: 300),
            ProcessUsage(pid: 4, name: "D", cpu: 0.5, memoryBytes: 900),
        ]
        let top = PanelFormat.topMemoryProcesses(procs, limit: 3)
        XCTAssertEqual(top.map(\.name), ["D", "B", "C"])
    }

    func testPortClassificationAndSamplerSmoke() {
        XCTAssertEqual(PortSampler.classify(port: 11434, processName: "ollama"), .ai)
        XCTAssertEqual(PortSampler.classify(port: 3000, processName: "node"), .web)
        XCTAssertEqual(PortSampler.classify(port: 5432, processName: "postgres"), .database)
        XCTAssertEqual(PortSampler.classify(port: 7895, processName: "mihomo"), .proxy)

        let ports = PortSampler().sample()
        // 验证不包含系统 AirPlay 和 49152+ 随机临时端口。
        for item in ports {
            XCTAssertLessThanOrEqual(item.port, 49_151)
            XCTAssertNotEqual(item.processName.lowercased(), "controlcenter")
            XCTAssertNotEqual(item.processName.lowercased(), "rapportd")
        }
    }

    func testThermalAndDiskSamplersSmoke() {
        var thermalSampler = ThermalSampler()
        let thermal = thermalSampler.sample()
        if let temp = thermal.temperatureCelsius {
            XCTAssertTrue((10.0...120.0).contains(temp))
        }
        if let gpuTemp = thermal.gpuTemperatureCelsius {
            XCTAssertTrue((10.0...120.0).contains(gpuTemp))
        }
        if let ssdTemp = thermal.ssdTemperatureCelsius {
            XCTAssertTrue((10.0...120.0).contains(ssdTemp))
        }

        var diskSampler = DiskSampler()
        diskSampler.prime()
        let disk = diskSampler.sample()
        XCTAssertGreaterThan(disk.totalBytes, 0)
        XCTAssertEqual(disk.breakdown.totalBytes, disk.totalBytes)
    }

    func testPanelViewRendersOffscreen() throws {
        let monitor = SystemMonitor.shared
        monitor.seedSnapshot(.sample)
        monitor.seedHistory(
            cpu: [0.22, 0.28, 0.35, 0.30, 0.42, 0.32],
            memory: [0.64, 0.65, 0.67, 0.68, 0.68],
            networkDown: [
                1_200_000, 2_800_000, 4_500_000, 3_100_000, 6_400_000, 8_200_000,
                5_400_000, 9_800_000, 11_200_000, 7_600_000, 12_400_000, 10_100_000,
                6_200_000, 4_800_000, 8_900_000, 12_000_000, 9_400_000, 5_100_000,
                3_200_000, 7_800_000, 11_500_000, 12_400_000, 8_300_000, 6_000_000,
            ],
            networkUp: [
                200_000, 500_000, 800_000, 1_100_000, 900_000, 1_800_000,
                1_400_000, 700_000, 1_200_000, 2_100_000, 1_800_000, 900_000,
                600_000, 1_500_000, 2_400_000, 1_600_000, 800_000, 1_100_000,
                1_900_000, 1_300_000, 950_000, 1_800_000, 1_200_000, 750_000,
            ],
            thermal: [42, 43, 44, 46, 48, 50, 53, 58, 63, 69, 72, 66, 58, 49, 43],
            power: [11.2, 12.8, 14.5, 16.0, 21.4, 28.6, 36.2, 31.8, 24.0, 19.5, 15.2, 13.8, 16.4, 22.1, 26.8, 21.0, 17.5, 18.4],
            diskRead: [
                12_000_000, 28_000_000, 64_000_000, 95_000_000, 140_000_000, 185_000_000,
                120_000_000, 52_000_000, 18_000_000, 84_000_000, 165_000_000, 210_000_000,
                150_000_000, 92_000_000, 48_000_000, 110_000_000, 175_000_000, 142_000_000,
            ],
            diskWrite: [
                8_000_000, 15_000_000, 22_000_000, 45_000_000, 80_000_000, 62_000_000,
                30_000_000, 18_000_000, 95_000_000, 128_000_000, 74_000_000, 40_000_000,
                25_000_000, 60_000_000, 88_000_000, 54_000_000, 38_000_000, 68_000_000,
            ]
        )

        let renderer = ImageRenderer(content: PanelView(monitor: monitor))
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage else {
            XCTFail("ImageRenderer failed to render PanelView")
            return
        }
        XCTAssertGreaterThan(nsImage.size.width, 300)
        XCTAssertGreaterThan(nsImage.size.height, 400)

        if let outPath = ProcessInfo.processInfo.environment["PEEK_PANEL_SNAPSHOT_OUT"],
            let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            try png.write(to: URL(fileURLWithPath: outPath))
        }
    }
}
