import Foundation

// Claude Code 会话名解析，对称于 CodexThreadNameIndex。
// 数据来源不同：Claude 用 ~/.claude/sessions/<pid>.json（含 rename 的 name 字段）
// + ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl（transcript 首问 fallback）。
// hostApplicationName 不在此实现（协议默认 nil）：Claude 宿主来自父链 agent，
// 由展示层 ActivityPresentation.sourceDetail 兜底，与 codex 的 rollout metadata 路径区分。
final class ClaudeThreadNameIndex: CodexThreadNameResolving {
    private struct ClaudeSessionFile: Decodable {
        let pid: Int?
        let sessionId: String?
        let cwd: String?
        let name: String?
    }

    private let sessionsRootURL: URL
    private let projectsRootURL: URL
    private let fileManager: FileManager

    private var cachedSessionsBySessionID: [String: ClaudeSessionFile] = [:]
    private var cachedTranscriptBySessionID: [String: URL] = [:]
    private var cacheLoadedAt: Date?
    private static let cacheTTL: TimeInterval = 5
    private static let maxFirstPromptScanBytes: Int = 256 * 1024

    init(
        sessionsRootURL: URL = ClaudeThreadNameIndex.defaultClaudeSessionsRootURL(),
        projectsRootURL: URL = ClaudeThreadNameIndex.defaultClaudeProjectsRootURL(),
        fileManager: FileManager = .default
    ) {
        self.sessionsRootURL = sessionsRootURL
        self.projectsRootURL = projectsRootURL
        self.fileManager = fileManager
    }

    static func defaultClaudeSessionsRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let explicit = environment["CLAUDE_SESSIONS_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    static func defaultClaudeProjectsRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let explicit = environment["CLAUDE_PROJECTS_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    func threadName(for sessionID: String) -> String? {
        guard let sessionId = CodexThreadNameIndex.threadID(from: sessionID) else { return nil }
        refreshIfNeeded()

        // 1) sessions/<pid>.json 的 name（/rename 后的名称）
        if let name = cachedSessionsBySessionID[sessionId]?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        // 2) transcript 首问 fallback（与 codex rollout 首问对称）
        guard let transcriptURL = cachedTranscriptBySessionID[sessionId] else { return nil }
        return firstUserPrompt(in: transcriptURL)
    }

    /// sessionID 对应的 claude 会话是否仍打开（~/.claude/sessions/<pid>.json 是否存在）。
    /// 用于过滤 hook 上报但已退出的会话残留。无法提取 sid 时保留（不过滤）。
    func isLiveSession(for sessionID: String) -> Bool {
        guard let sid = CodexThreadNameIndex.threadID(from: sessionID) else { return true }
        refreshIfNeeded()
        return cachedSessionsBySessionID[sid] != nil
    }

    // hostApplicationName 走协议默认 nil（见类注释）。

    private func refreshIfNeeded() {
        let now = Date()
        if let cacheLoadedAt, now.timeIntervalSince(cacheLoadedAt) < Self.cacheTTL {
            return
        }
        cacheLoadedAt = now
        cachedSessionsBySessionID = [:]
        cachedTranscriptBySessionID = [:]
        loadSessions()
        loadTranscriptsForOpenSessions()
    }

    private func loadSessions() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: sessionsRootURL,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            // 文件名是 <pid>.json
            guard file.deletingPathExtension().lastPathComponent.allSatisfy(\.isNumber),
                  let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(ClaudeSessionFile.self, from: data),
                  let sessionId = record.sessionId?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionId.isEmpty else { continue }
            cachedSessionsBySessionID[sessionId] = record
        }
    }

    // 只为「打开会话」（sessions/<pid>.json 里的 sessionId）定位 transcript，避免扫全量历史。
    private func loadTranscriptsForOpenSessions() {
        guard !cachedSessionsBySessionID.isEmpty else { return }
        let neededSessionIDs = Set(cachedSessionsBySessionID.keys)
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: projectsRootURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for dir in projectDirs {
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let sessionId = file.deletingPathExtension().lastPathComponent
                if neededSessionIDs.contains(sessionId) {
                    cachedTranscriptBySessionID[sessionId] = file
                }
            }
        }
    }

    private func firstUserPrompt(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let head = data.prefix(Self.maxFirstPromptScanBytes)
        guard let text = String(data: head, encoding: .utf8) else { return nil }

        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            guard (object["type"] as? String) == "user" else { continue }

            // 只取人类输入：origin.kind == human
            if let origin = object["origin"] as? [String: Any],
               let kind = origin["kind"] as? String,
               kind != "human" {
                continue
            }

            // message.content 是 String 才是真实首问；array 是 tool_result，跳过
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? String else { continue }

            let cleaned = cleanPrompt(content)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private func cleanPrompt(_ text: String) -> String {
        let compact = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "" : compact
    }
}
