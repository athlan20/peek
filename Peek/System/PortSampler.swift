import Darwin
import Foundation

/// 本机监听端口的语义分类，用于面板着色与优先级排序。
enum PortCategory: String, Sendable, Equatable {
    case web
    case ai
    case database
    case proxy
    case other

    var priority: Int {
        switch self {
        case .web: 0
        case .ai: 1
        case .database: 2
        case .proxy: 3
        case .other: 4
        }
    }
}

/// 一条已过滤的本机 TCP LISTEN 端口记录。
struct ListeningPort: Sendable, Equatable, Identifiable {
    var port: UInt16
    var pid: Int32
    var processName: String
    var bindAddress: String
    var category: PortCategory

    var id: String { "\(pid):\(port)" }

    /// 是否适合直接用浏览器打开 `http://localhost:<port>`。
    var isWebOpenable: Bool {
        category == .web || category == .ai || category == .proxy
    }
}

/// 原生 BSD 端口采集器：通过 `proc_listpids` + `proc_pidinfo(PROC_PIDLISTFDS)` + `PROC_PIDFDSOCKETINFO`
/// 枚举本机 TCP LISTEN 端口，不依赖 `lsof` 等外部命令；并自动过滤系统后台与随机临时 IPC 端口。
struct PortSampler {
    func sample() -> [ListeningPort] {
        var seen = Set<String>()
        var results: [ListeningPort] = []

        for pid in Self.allPIDs() where pid > 0 {
            let name = Self.processName(pid: pid)
            guard !name.isEmpty, !Self.isIgnoredProcess(name: name) else { continue }
            let path = Self.processPath(pid: pid)
            if let path, Self.isSystemPath(path) { continue }

            for socket in Self.listeningSockets(pid: pid) {
                // 过滤 49152+ 临时随机 IPC 端口（如 Electron / IDE / IM 内部通信端口）。
                guard socket.port > 0, socket.port <= 49_151 else { continue }

                let key = "\(pid):\(socket.port)"
                guard seen.insert(key).inserted else { continue }

                let category = Self.classify(port: socket.port, processName: name)
                results.append(
                    ListeningPort(
                        port: socket.port,
                        pid: pid,
                        processName: name,
                        bindAddress: socket.bindAddress,
                        category: category
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.category.priority != rhs.category.priority {
                return lhs.category.priority < rhs.category.priority
            }
            return lhs.port < rhs.port
        }
    }

    // MARK: - 智能过滤与分类

    private static let ignoredProcessNames: Set<String> = [
        "controlcenter", "rapportd", "sharingd", "airplayxpchelper",
        "mdnsresponder", "cupsd", "remoted", "identityservicesd",
        "bluetoothd", "mediasharingd", "ampdeviceagent", "netbiosd",
        "uniaccess", "uniaccessagent", "netdisk_sync", "netdisk_s",
    ]

    private static let systemPathPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/Library/Apple/",
    ]

    private static func isIgnoredProcess(name: String) -> Bool {
        ignoredProcessNames.contains(name.lowercased())
    }

    private static func isSystemPath(_ path: String) -> Bool {
        systemPathPrefixes.contains { path.hasPrefix($0) }
    }

    static func classify(port: UInt16, processName: String) -> PortCategory {
        let lower = processName.lowercased()

        // AI / 本地大模型服务
        if lower.contains("ollama") || lower.contains("lmstudio") || lower.contains("llama")
            || [11434, 1234, 7860, 8188].contains(port)
        {
            return .ai
        }

        // 数据库与基础设施
        if lower.contains("postgres") || lower.contains("redis") || lower.contains("mysql")
            || lower.contains("mongod") || lower.contains("clickhouse") || lower.contains("qdrant")
            || lower.contains("docker") || lower.contains("orbstack")
            || [5432, 3306, 6379, 27017, 9200, 6333, 18424].contains(port)
        {
            return .database
        }

        // 代理 / 网关工具
        if lower.contains("mihomo") || lower.contains("clash") || lower.contains("sing-box")
            || lower.contains("v2ray") || lower.contains("xray") || lower.contains("surge")
            || [7890, 7891, 7895, 7897, 9090].contains(port)
        {
            return .proxy
        }

        // Web / 开发运行时
        let devRuntimes = [
            "node", "bun", "deno", "python", "uvicorn", "gunicorn", "ruby",
            "go", "java", "php", "nginx", "caddy", "vite", "next", "esbuild",
            "dotnet", "beam.smp", "hugo", "jekyll", "webpack", "cargo",
        ]
        let isDevPort = (3000...3999).contains(port)
            || (4000...4999).contains(port)
            || (5170...5199).contains(port)
            || (8000...8999).contains(port)
            || port == 80 || port == 443
        if isDevPort || devRuntimes.contains(where: { lower.contains($0) }) {
            return .web
        }

        return .other
    }

    // MARK: - BSD proc_pidinfo 底层读取

    private static func allPIDs() -> [pid_t] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](
            repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride + 16)
        let used = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard used > 0 else { return [] }
        return Array(pids.prefix(Int(used) / MemoryLayout<pid_t>.stride)).filter { $0 > 0 }
    }

    private static func listeningSockets(pid: pid_t) -> [(port: UInt16, bindAddress: String)] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }

        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let count = Int(needed) / fdStride + 8
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let used = fds.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard used > 0 else { return [] }

        let actualCount = Int(used) / fdStride
        var sockets: [(UInt16, String)] = []

        for index in 0..<actualCount {
            let fd = fds[index]
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.stride)
            let read = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size)
            guard read == size else { continue }
            guard info.psi.soi_kind == SOCKINFO_TCP else { continue }

            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }

            let rawPort = UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)
            let port = UInt16(bigEndian: rawPort)
            guard port > 0 else { continue }

            let family = info.psi.soi_family
            let bindAddress = Self.formatBindAddress(ini: tcp.tcpsi_ini, family: family)
            sockets.append((port, bindAddress))
        }
        return sockets
    }

    private static func formatBindAddress(ini: in_sockinfo, family: Int32) -> String {
        if family == AF_INET {
            let addr = ini.insi_laddr.ina_46.i46a_addr4
            let raw = UInt32(bigEndian: addr.s_addr)
            if raw == 0 { return "*" }
            if raw == 0x7F00_0001 { return "127.0.0.1" }
            var a = addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            return "127.0.0.1"
        }
        if family == AF_INET6 {
            var a = ini.insi_laddr.ina_6
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if inet_ntop(AF_INET6, &a, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                let str = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if str == "::" { return "*" }
                if str == "::1" { return "127.0.0.1" }
                return str
            }
        }
        return "localhost"
    }

    private static func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static func processPath(pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE = 4096
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
