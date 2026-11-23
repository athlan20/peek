import Foundation

/// 方块视图里的类型。顺序就是图例的顺序。
enum AnalyzeCategory: String, CaseIterable, Sendable {
    case agent
    case apps
    case developer
    case media
    case documents
    case system
    case other
}

/// 一个 AI Agent:名字、主题色(没有公认品牌色就是 nil)、它在主目录下的目录。
struct AnalyzeAgent: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    /// 品牌主色 `0xRRGGBB`。
    let brandColor: UInt32?
    /// 相对主目录的路径。
    let paths: [String]
}

/// 给分析条目分类,规格见 `docs/analyze-treemap.md`。纯函数,传入主目录方便测试。
enum AnalyzeClassifier {
    static let agents: [AnalyzeAgent] = [
        AnalyzeAgent(
            id: "claude", name: "Claude Code", brandColor: 0xD97757,
            paths: [".claude", ".local/share/claude", "Library/Application Support/Claude", "Library/Caches/Claude"]),
        AnalyzeAgent(
            id: "codex", name: "Codex", brandColor: 0x10A37F,
            paths: [".codex", "Library/Application Support/Codex", "Library/Caches/Codex"]),
        AnalyzeAgent(id: "gemini", name: "Gemini CLI", brandColor: 0x4796E3, paths: [".gemini"]),
        AnalyzeAgent(id: "huggingface", name: "Hugging Face", brandColor: 0xFFD21E, paths: [".cache/huggingface"]),
        AnalyzeAgent(
            id: "cursor", name: "Cursor", brandColor: nil,
            paths: [".cursor", ".local/share/cursor-agent", "Library/Application Support/Cursor"]),
        AnalyzeAgent(id: "copilot", name: "GitHub Copilot", brandColor: nil, paths: [".copilot"]),
        AnalyzeAgent(
            id: "opencode", name: "opencode", brandColor: nil,
            paths: [".opencode", ".local/share/opencode", ".config/opencode"]),
        AnalyzeAgent(id: "ollama", name: "Ollama", brandColor: nil, paths: [".ollama"]),
        AnalyzeAgent(id: "lmstudio", name: "LM Studio", brandColor: nil, paths: [".lmstudio", ".cache/lm-studio"]),
        AnalyzeAgent(
            id: "windsurf", name: "Windsurf", brandColor: nil,
            paths: [".windsurf", ".codeium", "Library/Application Support/Windsurf"]),
        AnalyzeAgent(id: "kiro", name: "Kiro", brandColor: nil, paths: [".kiro", "Library/Application Support/Kiro"]),
        AnalyzeAgent(id: "trae", name: "Trae", brandColor: nil, paths: [".trae", "Library/Application Support/Trae"]),
        AnalyzeAgent(id: "continue", name: "Continue", brandColor: nil, paths: [".continue"]),
        AnalyzeAgent(id: "aider", name: "Aider", brandColor: nil, paths: [".aider"]),
        AnalyzeAgent(id: "qwen", name: "Qwen Code", brandColor: nil, paths: [".qwen"]),
        AnalyzeAgent(id: "t3", name: "T3 Code", brandColor: nil, paths: [".t3"]),
        AnalyzeAgent(id: "pi", name: "pi", brandColor: nil, paths: [".pi"]),
        AnalyzeAgent(
            id: "workbuddy", name: "WorkBuddy", brandColor: nil,
            paths: [
                ".workbuddy", ".workbuddy-ai", "Library/Application Support/WorkBuddy",
                "Library/Application Support/com.tencent.workbuddy.mac",
                "Library/Caches/com.tencent.workbuddy.mac",
                "Library/Caches/com.tencent.workbuddy.mac.BundleMigration",
            ]),
        AnalyzeAgent(
            id: "codebuddy", name: "CodeBuddy", brandColor: nil,
            paths: [
                ".codebuddy", ".codebuddycn", "Library/Application Support/CodeBuddy CN",
                "Library/Application Support/CodeBuddyExtension",
            ]),
    ]

    /// 路径里出现就算开发的目录名。
    private static let developerComponents: Set<String> = [
        "node_modules", "DerivedData", ".npm", ".yarn", ".pnpm-store", ".bun", ".cargo", ".rustup",
        ".gradle", ".m2", ".ivy2", ".sbt", ".cocoapods", ".pub-cache", ".nuget", ".dotnet", ".pyenv",
        ".rbenv", ".nvm", ".volta", ".conda", ".swiftpm", "CoreSimulator", ".venv", "venv", "Pods",
    ]
    /// 主目录下直接一层就算开发的目录名。
    private static let developerHomeChildren: Set<String> = [
        "Developer", "work", "Work", "Projects", "projects", "GitHub", "github", "dev", "code", "Code",
        "src", "go", ".cache", ".docker", ".vscode", ".vscode-server", ".android", ".gem",
        "miniconda3", "anaconda3", "miniforge3",
    ]
    private static let developerExtensions: Set<String> = ["xcarchive", "xcodeproj", "xcworkspace"]

    private static let mediaHomeChildren: Set<String> = ["Movies", "Music", "Pictures"]
    private static let mediaExtensions: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle", "logicx",
        "mov", "mp4", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "wav", "flac", "aac", "aiff",
        "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff", "webp", "raw", "dng", "cr2", "cr3", "nef", "arw", "psd",
    ]

    private static let documentHomeChildren: Set<String> = ["Documents", "Desktop", "Downloads"]
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "md", "rtf",
        "epub", "csv", "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "dmg", "pkg", "iso",
    ]

    private static let systemRootChildren: Set<String> = [
        "System", "Library", "private", "usr", "bin", "sbin", "opt", "cores", "var", "etc", "tmp",
    ]

    /// 条目属于哪个 Agent:路径等于 Agent 的某个目录,或在它里面。
    static func agent(for url: URL, home: URL) -> AnalyzeAgent? {
        // Agent 页第一层的虚拟条目。
        if let id = AnalyzeAgentScan.agentID(from: url) {
            return agents.first { $0.id == id }
        }
        guard url.isFileURL, let relative = relativeComponents(of: url, to: home), !relative.isEmpty else { return nil }
        for agent in agents {
            for path in agent.paths {
                let parts = path.split(separator: "/").map(String.init)
                if relative.count >= parts.count, Array(relative.prefix(parts.count)) == parts {
                    return agent
                }
            }
        }
        return nil
    }

    static func category(for url: URL, isDirectory: Bool, home: URL) -> AnalyzeCategory {
        if agent(for: url, home: home) != nil { return .agent }

        let components = url.standardizedFileURL.pathComponents
        let ext = url.pathExtension.lowercased()
        let relative = relativeComponents(of: url, to: home)

        if ext == "app" { return .apps }
        if components.count >= 2, components[1] == "Applications" { return .apps }
        if let relative, relative.first == "Applications" { return .apps }

        if components.contains(where: developerComponents.contains) || developerExtensions.contains(ext) {
            return .developer
        }
        if let first = relative?.first, developerHomeChildren.contains(first) { return .developer }
        // Xcode、模拟器都在 ~/Library/Developer。
        if let relative, relative.count >= 2, relative[0] == "Library", relative[1] == "Developer" {
            return .developer
        }

        if let first = relative?.first, mediaHomeChildren.contains(first) { return .media }
        if mediaExtensions.contains(ext) { return .media }

        if let first = relative?.first, documentHomeChildren.contains(first) { return .documents }
        if !isDirectory || ext == "pkg", documentExtensions.contains(ext) { return .documents }

        if let first = relative?.first, first == "Library" { return .system }
        if relative == nil, components.count >= 2, systemRootChildren.contains(components[1]) { return .system }

        return .other
    }

    /// `url` 相对 `home` 的路径分段;不在主目录里返回 nil,就是主目录本身返回空数组。
    private static func relativeComponents(of url: URL, to home: URL) -> [String]? {
        let path = url.standardizedFileURL.pathComponents
        let base = home.standardizedFileURL.pathComponents
        guard path.count >= base.count, Array(path.prefix(base.count)) == base else { return nil }
        return Array(path.dropFirst(base.count))
    }
}
