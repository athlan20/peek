import AppKit
import CryptoKit
import Foundation
import Observation

/// 语义化版本号解析与比较（支持 `v0.2.0`、`0.10.1`、`1.2` 等格式）。
struct SemVer: Comparable, Sendable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let core = stripped.split(separator: "-", maxSplits: 1).first.map(String.init) ?? stripped
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// 从 GitHub Releases 解析出的可更新版本元数据。
struct UpdateRelease: Sendable, Equatable {
    let version: String
    let tagName: String
    let notes: String
    let assetName: String
    let downloadURL: URL
    let sha256AssetURL: URL?
    let releasePageURL: URL
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateRelease)
    case downloading(UpdateRelease, progress: Double)
    case verifying(UpdateRelease)
    case relaunching
    case failed(String)
}

/// 原生轻量在线升级器：对接 GitHub Releases（`athlan20/peek`），
/// 零第三方框架依赖，支持架构自动匹配、SHA-256 与证书指纹双重校验、原子替换并重启。
@MainActor
@Observable
final class UpdateManager {
    static let shared = UpdateManager()

    nonisolated static let repoSlug = "athlan20/peek"
    static let autoCheckKey = "peek.update.autoCheck"
    static let lastCheckKey = "peek.update.lastCheckAt"
    static let lastFailedCheckKey = "peek.update.lastFailedCheckAt"
    private nonisolated static let checkInterval: TimeInterval = 24 * 60 * 60
    /// 静默检查失败后的重试间隔：比成功后的 24 小时短，但避免每次打开面板都重复请求。
    private nonisolated static let failedRetryInterval: TimeInterval = 60 * 60
    nonisolated static let latestReleasePageURL = URL(string: "https://github.com/\(repoSlug)/releases/latest")!

    private(set) var state: UpdateState = .idle
    var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey)
        }
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    nonisolated static var currentArch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    var availableRelease: UpdateRelease? {
        switch state {
        case .available(let rel), .downloading(let rel, _), .verifying(let rel):
            return rel
        default:
            return nil
        }
    }

    private var activeTask: Task<Void, Never>?

    private init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckEnabled = true
        } else {
            self.autoCheckEnabled = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        }
    }

    /// 面板打开时静默检查（默认开启，24 小时内最多请求一次 GitHub API）。
    func checkOnLaunchIfNeeded() {
        guard autoCheckEnabled else { return }
        let defaults = UserDefaults.standard
        guard Self.shouldAutoCheck(
            now: Date(),
            lastSuccess: defaults.object(forKey: Self.lastCheckKey) as? Date,
            lastFailure: defaults.object(forKey: Self.lastFailedCheckKey) as? Date
        ) else {
            return
        }
        checkForUpdates(manual: false)
    }

    /// 成功后 24 小时内不再检查；失败后 1 小时内不再检查（手动检查不受限制）。
    nonisolated static func shouldAutoCheck(now: Date, lastSuccess: Date?, lastFailure: Date?) -> Bool {
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < checkInterval {
            return false
        }
        if let lastFailure, now.timeIntervalSince(lastFailure) < failedRetryInterval {
            return false
        }
        return true
    }

    /// 主动或静默检查 GitHub Releases 最新版本。
    func checkForUpdates(manual: Bool = true) {
        switch state {
        case .checking, .downloading, .verifying, .relaunching:
            return
        default:
            break
        }

        if manual {
            state = .checking
        }

        let current = currentVersion
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            let outcome = await Self.fetchLatestRelease(currentVersion: current, arch: Self.currentArch)
            guard let self, !Task.isCancelled else { return }

            let defaults = UserDefaults.standard
            switch outcome {
            case .updateAvailable(let release):
                defaults.set(Date(), forKey: Self.lastCheckKey)
                defaults.removeObject(forKey: Self.lastFailedCheckKey)
                self.state = .available(release)
            case .upToDate:
                defaults.set(Date(), forKey: Self.lastCheckKey)
                defaults.removeObject(forKey: Self.lastFailedCheckKey)
                if manual || self.availableRelease == nil {
                    self.state = .upToDate(Date())
                }
            case .error(let message):
                defaults.set(Date(), forKey: Self.lastFailedCheckKey)
                if manual {
                    self.state = .failed(message)
                }
            }
        }
    }

    /// 下载对应架构的 `.zip`，依次做 SHA-256、签名与证书指纹校验，通过后原子替换并重启。
    func downloadAndInstall(_ release: UpdateRelease) {
        let currentAppURL = Bundle.main.bundleURL
        let parentDir = currentAppURL.deletingLastPathComponent()

        // 若当前在只读卷（如挂载的 .dmg）或无写权限，引导到 GitHub Release 页手动下载。
        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            NSWorkspace.shared.open(release.releasePageURL)
            state = .failed(L10n.text("Install Peek in /Applications to enable one-click updates."))
            return
        }

        state = .downloading(release, progress: 0.05)
        let currentBundleID = Bundle.main.bundleIdentifier
        let expectedLeafHash = Self.extractLeafCertHash(appURL: currentAppURL)

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                let zipURL = try await Self.downloadFile(from: release.downloadURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.state = .downloading(release, progress: progress)
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.state = .verifying(release)

                // 1. 如 Release 附带 SHA256SUMS.txt，先校验压缩包哈希。
                if let shaURL = release.sha256AssetURL {
                    try await Self.verifySHA256(zipURL: zipURL, assetName: release.assetName, sumsURL: shaURL)
                }

                // 2. 解压到隔离临时目录并校验签名与证书指纹。
                let stagedApp = try await Self.extractAndVerify(
                    zipURL: zipURL,
                    expectedBundleID: currentBundleID,
                    expectedLeafHash: expectedLeafHash
                )

                self.state = .relaunching
                try Self.scheduleAtomicReplaceAndRelaunch(
                    currentApp: currentAppURL,
                    stagedApp: stagedApp,
                    stagingRoot: stagedApp.deletingLastPathComponent()
                )
                NSApplication.shared.terminate(nil)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasePage(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.releasePageURL)
    }

    /// 检查或安装失败时的兜底：打开 GitHub 最新 Release 页手动下载。
    func openLatestReleasePage() {
        NSWorkspace.shared.open(Self.latestReleasePageURL)
    }

    // MARK: - GitHub API & Parsing (Testable)

    enum CheckOutcome: Sendable {
        case updateAvailable(UpdateRelease)
        case upToDate
        case error(String)
    }

    struct GitHubAsset: Decodable, Sendable {
        let name: String
        let browser_download_url: String
    }

    struct GitHubReleasePayload: Decodable, Sendable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [GitHubAsset]
    }

    /// 从 GitHub Release 载荷中匹配对应架构的 `.zip` 资产并判断是否为更新版本。
    nonisolated static func evaluateRelease(
        _ payload: GitHubReleasePayload,
        currentVersion: String,
        arch: String
    ) -> UpdateRelease? {
        if payload.draft == true || payload.prerelease == true { return nil }
        guard let latest = SemVer(payload.tag_name),
            let current = SemVer(currentVersion),
            latest > current
        else {
            return nil
        }

        let archSuffix = "-\(arch).zip"
        guard let asset = payload.assets.first(where: {
            $0.name.lowercased().hasSuffix(archSuffix)
        }) ?? payload.assets.first(where: {
            $0.name.lowercased().hasSuffix(".zip") && !$0.name.contains("x86_64") && !$0.name.contains("arm64")
        }),
            let downloadURL = URL(string: asset.browser_download_url),
            let pageURL = URL(string: payload.html_url)
        else {
            return nil
        }

        let shaURL = payload.assets
            .first(where: { $0.name.caseInsensitiveCompare("SHA256SUMS.txt") == .orderedSame })
            .flatMap { URL(string: $0.browser_download_url) }

        let cleanVersion = payload.tag_name.hasPrefix("v") || payload.tag_name.hasPrefix("V")
            ? String(payload.tag_name.dropFirst())
            : payload.tag_name

        return UpdateRelease(
            version: cleanVersion,
            tagName: payload.tag_name,
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            assetName: asset.name,
            downloadURL: downloadURL,
            sha256AssetURL: shaURL,
            releasePageURL: pageURL
        )
    }

    /// 从 GitHub Releases 重定向后的页面 URL（`/releases/tag/<tag>`）提取 tag 名。
    nonisolated static func extractTagName(fromReleaseURL url: URL) -> String? {
        let components = url.pathComponents
        guard let releasesIndex = components.firstIndex(of: "releases"),
            releasesIndex + 2 < components.count,
            components[releasesIndex + 1] == "tag"
        else {
            return nil
        }
        let tag = components[releasesIndex + 2].trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    /// 当 GitHub REST API 触发限流（HTTP 403/429）时，基于 tag 名与约定资产命名（或 `SHA256SUMS.txt`）构造更新元数据。
    nonisolated static func buildFallbackRelease(
        tagName: String,
        currentVersion: String,
        arch: String,
        sha256SumsText: String? = nil
    ) -> UpdateRelease? {
        guard let latest = SemVer(tagName),
            let current = SemVer(currentVersion),
            latest > current
        else {
            return nil
        }

        let cleanVersion = tagName.hasPrefix("v") || tagName.hasPrefix("V")
            ? String(tagName.dropFirst())
            : tagName

        let archSuffix = "-\(arch).zip"
        let assetName: String
        if let sha256SumsText {
            let fileNames = parseAssetNames(fromSHA256Sums: sha256SumsText)
            if let matched = fileNames.first(where: { $0.lowercased().hasSuffix(archSuffix) })
                ?? fileNames.first(where: {
                    $0.lowercased().hasSuffix(".zip") && !$0.contains("x86_64") && !$0.contains("arm64")
                })
            {
                assetName = matched
            } else if !fileNames.isEmpty {
                // SHA256SUMS.txt 存在但未包含当前架构的 .zip 资产。
                return nil
            } else {
                assetName = "Peek-\(cleanVersion)-\(arch).zip"
            }
        } else {
            assetName = "Peek-\(cleanVersion)-\(arch).zip"
        }

        guard let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedAsset = assetName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let downloadURL = URL(string: "https://github.com/\(repoSlug)/releases/download/\(encodedTag)/\(encodedAsset)"),
            let pageURL = URL(string: "https://github.com/\(repoSlug)/releases/tag/\(encodedTag)")
        else {
            return nil
        }

        let shaURL = URL(string: "https://github.com/\(repoSlug)/releases/download/\(encodedTag)/SHA256SUMS.txt")

        return UpdateRelease(
            version: cleanVersion,
            tagName: tagName,
            notes: "",
            assetName: assetName,
            downloadURL: downloadURL,
            sha256AssetURL: shaURL,
            releasePageURL: pageURL
        )
    }

    /// 从 `SHA256SUMS.txt` 中按行提取所有资产文件名。
    nonisolated static func parseAssetNames(fromSHA256Sums text: String) -> [String] {
        var names: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            let filePart = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let baseName = URL(fileURLWithPath: filePart).lastPathComponent
            if hash.count == 64, !baseName.isEmpty {
                names.append(baseName)
            }
        }
        return names
    }

    /// 解析 `shasum -a 256` 格式文本，按文件名提取期望 SHA-256（小写 hex）。
    nonisolated static func parseSHA256(from text: String, assetName: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            let filePart = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let baseName = URL(fileURLWithPath: filePart).lastPathComponent
            if baseName == assetName, hash.count == 64 {
                return hash
            }
        }
        return nil
    }

    /// 从 `codesign -d -r-` 输出中提取 `certificate leaf = H"<hex>"` 指纹。
    nonisolated static func parseLeafCertHash(from requirementOutput: String) -> String? {
        guard let marker = requirementOutput.range(of: "certificate leaf = H\"") else { return nil }
        let tail = requirementOutput[marker.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        let hex = String(tail[..<end]).lowercased()
        return hex.isEmpty ? nil : hex
    }

    // MARK: - Network & Verification Internals

    private nonisolated static func fetchLatestRelease(
        currentVersion: String,
        arch: String
    ) async -> CheckOutcome {
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else {
            return .error(L10n.text("Invalid release URL"))
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Peek/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error(L10n.text("Invalid server response"))
            }
            if http.statusCode == 404 {
                // 尚无已发布的 Release，按最新处理。
                return .upToDate
            }
            if http.statusCode == 403 || http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                // 共享出口 IP（代理/公司网等）容易触发 api.github.com 匿名限流（60 次/小时，返回 403/429），
                // 自动回退到无 API 限流的 github.com/releases/latest 302 重定向。
                let fallback = await fetchLatestReleaseViaWebRedirect(currentVersion: currentVersion, arch: arch)
                if case .error = fallback {
                    return .error(L10n.text("GitHub API returned HTTP \(http.statusCode)"))
                }
                return fallback
            }
            guard (200..<300).contains(http.statusCode) else {
                return .error(L10n.text("GitHub API returned HTTP \(http.statusCode)"))
            }
            let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
            if let release = evaluateRelease(payload, currentVersion: currentVersion, arch: arch) {
                return .updateAvailable(release)
            }
            return .upToDate
        } catch {
            let fallback = await fetchLatestReleaseViaWebRedirect(currentVersion: currentVersion, arch: arch)
            if case .error = fallback {
                return .error(error.localizedDescription)
            }
            return fallback
        }
    }

    /// 兜底检查：通过 `https://github.com/<repo>/releases/latest` 的重定向地址获取最新 tag，
    /// 不受 `api.github.com` 60 次/小时匿名限流影响。
    private nonisolated static func fetchLatestReleaseViaWebRedirect(
        currentVersion: String,
        arch: String
    ) async -> CheckOutcome {
        var request = URLRequest(url: latestReleasePageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        request.setValue("Peek/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error(L10n.text("Invalid server response"))
            }
            if http.statusCode == 404 {
                return .upToDate
            }
            guard (200..<300).contains(http.statusCode), let finalURL = http.url else {
                return .error(L10n.text("GitHub API returned HTTP \(http.statusCode)"))
            }
            guard let tagName = extractTagName(fromReleaseURL: finalURL) else {
                if finalURL.path.hasSuffix("/releases") {
                    return .upToDate
                }
                return .error(L10n.text("Invalid server response"))
            }

            guard let latest = SemVer(tagName),
                let current = SemVer(currentVersion),
                latest > current
            else {
                return .upToDate
            }

            // 尝试读取 SHA256SUMS.txt 以精确匹配当前架构的 .zip 文件名（同样走 github.com，无 API 限流）。
            var shaSumsText: String?
            if let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                let sumsURL = URL(string: "https://github.com/\(repoSlug)/releases/download/\(encodedTag)/SHA256SUMS.txt")
            {
                var sumsRequest = URLRequest(url: sumsURL)
                sumsRequest.setValue("Peek/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                sumsRequest.timeoutInterval = 10
                if let (sumsData, sumsResponse) = try? await URLSession.shared.data(for: sumsRequest),
                    let sumsHTTP = sumsResponse as? HTTPURLResponse,
                    (200..<300).contains(sumsHTTP.statusCode),
                    let text = String(data: sumsData, encoding: .utf8)
                {
                    shaSumsText = text
                }
            }

            if let release = buildFallbackRelease(
                tagName: tagName,
                currentVersion: currentVersion,
                arch: arch,
                sha256SumsText: shaSumsText
            ) {
                return .updateAvailable(release)
            }
            return .upToDate
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private nonisolated static func downloadFile(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let expectedLength = response.expectedContentLength
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destFile = destDir.appendingPathComponent("update.zip")
        FileManager.default.createFile(atPath: destFile.path, contents: nil)

        let handle = try FileHandle(forWritingTo: destFile)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var downloaded: Int64 = 0
        var lastReported = 0.0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 32 * 1024 {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    let ratio = min(0.98, Double(downloaded) / Double(expectedLength))
                    if ratio - lastReported >= 0.03 {
                        lastReported = ratio
                        onProgress(ratio)
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        onProgress(1.0)
        return destFile
    }

    private nonisolated static func verifySHA256(
        zipURL: URL,
        assetName: String,
        sumsURL: URL
    ) async throws {
        let (data, response) = try await URLSession.shared.data(from: sumsURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let text = String(data: data, encoding: .utf8),
            let expected = parseSHA256(from: text, assetName: assetName)
        else {
            return
        }

        let zipData = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: zipData)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw UpdateError.checksumMismatch
        }
    }

    private nonisolated static func extractAndVerify(
        zipURL: URL,
        expectedBundleID: String?,
        expectedLeafHash: String?
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let extractDir = zipURL.deletingLastPathComponent()
                .appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            guard runProcess("/usr/bin/ditto", ["-xk", zipURL.path, extractDir.path]).status == 0 else {
                throw UpdateError.extractFailed
            }

            let items = try FileManager.default.contentsOfDirectory(
                at: extractDir, includingPropertiesForKeys: nil)
            guard let appURL = items.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.appNotFoundInArchive
            }

            // 1. 严格校验代码签名完整性
            guard runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path]).status == 0 else {
                throw UpdateError.invalidSignature
            }

            // 2. 校验 Bundle ID
            if let expectedBundleID,
                let newBundleID = Bundle(url: appURL)?.bundleIdentifier,
                newBundleID != expectedBundleID
            {
                throw UpdateError.bundleIDMismatch
            }

            // 3. 校验叶证书指纹一致性，确保升级后系统授权（完全磁盘访问等）不丢失
            if let expectedLeafHash {
                guard let newLeafHash = extractLeafCertHash(appURL: appURL),
                    newLeafHash == expectedLeafHash
                else {
                    throw UpdateError.certificateMismatch
                }
            }

            return appURL
        }.value
    }

    private nonisolated static func extractLeafCertHash(appURL: URL) -> String? {
        let res = runProcess("/usr/bin/codesign", ["-d", "-r-", appURL.path])
        guard res.status == 0 else { return nil }
        return parseLeafCertHash(from: res.output)
    }

    private nonisolated static func scheduleAtomicReplaceAndRelaunch(
        currentApp: URL,
        stagedApp: URL,
        stagingRoot: URL
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        PID="\(pid)"
        TARGET="$1"
        STAGED="$2"
        STAGE_ROOT="$3"
        BACKUP="${TARGET}.peek-backup"

        for _ in $(seq 1 50); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done

        rm -rf "$BACKUP"
        if mv "$TARGET" "$BACKUP"; then
            if mv "$STAGED" "$TARGET"; then
                rm -rf "$BACKUP" "$STAGE_ROOT"
                xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
                open -n "$TARGET"
                exit 0
            else
                mv "$BACKUP" "$TARGET" 2>/dev/null || true
            fi
        fi
        exit 1
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script, "peek-updater", currentApp.path, stagedApp.path, stagingRoot.path]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }

    private nonisolated static func runProcess(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }
}

private enum UpdateError: LocalizedError {
    case downloadFailed
    case checksumMismatch
    case extractFailed
    case appNotFoundInArchive
    case invalidSignature
    case bundleIDMismatch
    case certificateMismatch

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return L10n.text("Failed to download update package.")
        case .checksumMismatch: return L10n.text("SHA-256 checksum verification failed.")
        case .extractFailed: return L10n.text("Failed to extract update archive.")
        case .appNotFoundInArchive: return L10n.text("Update archive does not contain Peek.app.")
        case .invalidSignature: return L10n.text("Update signature verification failed.")
        case .bundleIDMismatch: return L10n.text("Update Bundle ID does not match Peek.")
        case .certificateMismatch: return L10n.text("Update certificate does not match the current app.")
        }
    }
}
