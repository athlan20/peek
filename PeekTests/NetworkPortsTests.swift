import CoreGraphics
import Darwin
import XCTest
@testable import Peek

final class NetworkPortsTests: XCTestCase {
    private let samplePorts: [ListeningPort] = [
        ListeningPort(port: 3000, pid: 101, processName: "node", bindAddress: "127.0.0.1", category: .web, executablePath: "/usr/local/bin/node", establishedCount: 2),
        ListeningPort(port: 5173, pid: 101, processName: "node", bindAddress: "*", category: .web, executablePath: "/usr/local/bin/node", establishedCount: 1),
        ListeningPort(port: 8080, pid: 202, processName: "Node", bindAddress: "127.0.0.1", category: .web, executablePath: "/opt/homebrew/bin/node", establishedCount: 0),
        ListeningPort(port: 11434, pid: 303, processName: "ollama", bindAddress: "127.0.0.1", category: .ai, executablePath: "/Applications/Ollama.app/Contents/Resources/ollama", establishedCount: 0),
        ListeningPort(port: 5432, pid: 404, processName: "postgres", bindAddress: "127.0.0.1", category: .database, executablePath: "/opt/homebrew/bin/postgres", establishedCount: 4),
        ListeningPort(port: 7890, pid: 505, processName: "mihomo", bindAddress: "*", category: .proxy, executablePath: "/usr/local/bin/mihomo", establishedCount: 9),
    ]

    func testGroupByProcessMergesCaseInsensitivelyAndSortsByCountThenPriority() {
        let groups = NetworkPortGroups.groupByProcess(samplePorts)
        XCTAssertEqual(groups.count, 4)

        // node 有 3 个端口，排第一；且合并了 "node" 和 "Node"，包含 2 个不同 PID
        XCTAssertEqual(groups[0].id, "node")
        XCTAssertEqual(groups[0].ports.map(\.port), [3000, 5173, 8080])
        XCTAssertEqual(groups[0].pids, [101, 202])
        XCTAssertEqual(groups[0].dominantCategory, .web)
        XCTAssertEqual(groups[0].totalEstablished, 3)

        // 其余均为 1 个端口，按分类优先级 ai < database < proxy 排序
        XCTAssertEqual(groups[1].processName, "ollama")
        XCTAssertEqual(groups[2].processName, "postgres")
        XCTAssertEqual(groups[3].processName, "mihomo")

        // 多端口组的 treemapWeight 明显大于单端口组
        XCTAssertGreaterThan(groups[0].treemapWeight, groups[1].treemapWeight)
    }

    func testFilterMatchesPortWithOrWithoutColonAndProcessAndPIDAndCategory() {
        let byPort = NetworkPortGroups.filter(samplePorts, query: ":5173", category: nil)
        XCTAssertEqual(byPort.map(\.port), [5173])

        let byPID = NetworkPortGroups.filter(samplePorts, query: "404", category: nil)
        XCTAssertEqual(byPID.map(\.processName), ["postgres"])

        let byCategory = NetworkPortGroups.filter(samplePorts, query: "", category: .ai)
        XCTAssertEqual(byCategory.map(\.port), [11434])

        let byPath = NetworkPortGroups.filter(samplePorts, query: "homebrew", category: nil)
        XCTAssertEqual(Set(byPath.map(\.port)), [8080, 5432])
    }

    func testPortsSharingPIDFindsAllPortsForMultiPortProcess() {
        let shared = NetworkPortGroups.portsSharingPID(101, in: samplePorts)
        XCTAssertEqual(shared.map(\.port), [3000, 5173])

        let single = NetworkPortGroups.portsSharingPID(303, in: samplePorts)
        XCTAssertEqual(single.map(\.port), [11434])
    }

    func testBentoRowsPackMultiSpanGroupsCleanlyWithoutSlivers() {
        // 3 列栅格下：mihomo(2) + node(1) 凑满第 1 行；ollama(1) + postgres(1) + netdisk(1) 凑满第 2 行；uni(1) 第 3 行
        let ports = [
            ListeningPort(port: 7895, pid: 753, processName: "mihomo", bindAddress: "127.0.0.1", category: .proxy),
            ListeningPort(port: 9090, pid: 753, processName: "mihomo", bindAddress: "127.0.0.1", category: .proxy),
            ListeningPort(port: 7265, pid: 1319, processName: "node", bindAddress: "127.0.0.1", category: .web),
            ListeningPort(port: 11434, pid: 742, processName: "ollama", bindAddress: "127.0.0.1", category: .ai),
            ListeningPort(port: 18424, pid: 758, processName: "postgres", bindAddress: "127.0.0.1", category: .database),
            ListeningPort(port: 10000, pid: 760, processName: "netdisk_service", bindAddress: "127.0.0.1", category: .other),
            ListeningPort(port: 11301, pid: 761, processName: "UniService", bindAddress: "*", category: .other),
        ]
        let groups = NetworkPortGroups.groupByProcess(ports)
        let rows = NetworkPortGroups.bentoRows(for: groups, totalColumns: 3)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].slots.map(\.span), [2, 1])
        XCTAssertEqual(rows[0].slots.map(\.group.processName), ["mihomo", "node"])
        XCTAssertEqual(rows[1].slots.map(\.span), [1, 1, 1])
        XCTAssertEqual(rows[2].slots.map(\.span), [1])
        XCTAssertEqual(NetworkPortGroups.totalColumns(forWidth: 640), 3)
        XCTAssertEqual(NetworkPortGroups.totalColumns(forWidth: 860), 4)
    }

    func testListeningPortCopyableAddressAndExposure() {
        let web = samplePorts[0]
        XCTAssertEqual(web.copyableAddress, "http://localhost:3000")
        XCTAssertFalse(web.isExposedExternally)

        let exposedWeb = samplePorts[1]
        XCTAssertTrue(exposedWeb.isExposedExternally)

        let db = samplePorts[4]
        XCTAssertEqual(db.copyableAddress, "localhost:5432")
    }

    func testPortProcessTerminatorGuardsProtectedPIDsAndMapsOutcomes() {
        XCTAssertEqual(
            PortProcessTerminator.terminate(pid: 0, currentPID: 999) { _, _ in
                XCTFail("Should not signal pid 0")
                return 0
            },
            .protectedProcess
        )
        XCTAssertEqual(
            PortProcessTerminator.terminate(pid: 1, currentPID: 999) { _, _ in
                XCTFail("Should not signal pid 1")
                return 0
            },
            .protectedProcess
        )
        XCTAssertEqual(
            PortProcessTerminator.terminate(pid: 999, currentPID: 999) { _, _ in
                XCTFail("Should not signal self")
                return 0
            },
            .protectedProcess
        )

        let terminated = PortProcessTerminator.terminate(pid: 1234, currentPID: 999) { pid, sig in
            XCTAssertEqual(pid, 1234)
            XCTAssertEqual(sig, SIGTERM)
            return 0
        }
        XCTAssertEqual(terminated, .terminated)

        let denied = PortProcessTerminator.terminate(pid: 1234, currentPID: 999) { _, _ in
            errno = EPERM
            return -1
        }
        XCTAssertEqual(denied, .permissionDenied)

        let gone = PortProcessTerminator.terminate(pid: 1234, currentPID: 999) { _, _ in
            errno = ESRCH
            return -1
        }
        XCTAssertEqual(gone, .alreadyExited)
    }
}
