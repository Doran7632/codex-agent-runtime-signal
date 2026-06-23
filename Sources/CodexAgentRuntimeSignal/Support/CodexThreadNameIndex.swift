import Foundation

struct CodexIndexedSession: Equatable, Sendable {
    let threadID: String
    let threadName: String
    let updatedAt: Date?
    let hostApplicationName: String?
}

protocol CodexThreadNameResolving: AnyObject {
    func threadName(for sessionID: String) -> String?
    func hostApplicationName(for sessionID: String) -> String?
    func indexedSessions() -> [CodexIndexedSession]
    func knownSessions() -> [CodexIndexedSession]
}

extension CodexThreadNameResolving {
    func hostApplicationName(for sessionID: String) -> String? {
        nil
    }

    func indexedSessions() -> [CodexIndexedSession] {
        []
    }

    func knownSessions() -> [CodexIndexedSession] {
        indexedSessions()
    }
}

final class CodexThreadNameIndex: CodexThreadNameResolving {
    private struct IndexRecord: Decodable {
        let id: String
        let threadName: String
        let updatedAt: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
            case updatedAt = "updated_at"
        }
    }

    private struct CachedIndexSession {
        let threadID: String
        let threadName: String
        let updatedAt: Date?
        let order: Int
    }

    private struct RolloutSessionFile {
        let threadID: String
        let url: URL
        let modificationDate: Date?
    }

    private let indexURL: URL
    private let sessionsRootURL: URL
    private let fileManager: FileManager
    private var cachedModificationDate: Date?
    private var cachedNamesByID: [String: String] = [:]
    private var cachedIndexSessionsByID: [String: CachedIndexSession] = [:]
    private var cachedSessionMetadataByID: [String: CachedSessionMetadata] = [:]
    private var cachedKnownSessionsLoadedAt: Date?
    private var cachedKnownSessions: [CodexIndexedSession] = []
    private var cachedRolloutFilesLoadedAt: Date?
    private var cachedRolloutFiles: [RolloutSessionFile] = []
    private var cachedRolloutFilesByThreadID: [String: [RolloutSessionFile]] = [:]
    private static let knownSessionsCacheTTL: TimeInterval = 5
    private static let rolloutFilesCacheTTL: TimeInterval = 5
    private static let maxSessionMetadataHeadBytes: UInt64 = 1024 * 1024
    private static let maxSessionMetadataTailBytes: UInt64 = 256 * 1024

    private struct SessionMetadata {
        let threadName: String?
        let hostApplicationName: String?
    }

    private struct CachedSessionMetadata {
        let fileURL: URL
        let modificationDate: Date?
        let metadata: SessionMetadata
    }

    init(
        indexURL: URL = CodexThreadNameIndex.defaultIndexURL(),
        sessionsRootURL: URL = CodexThreadNameIndex.defaultSessionsRootURL(),
        fileManager: FileManager = .default
    ) {
        self.indexURL = indexURL
        self.sessionsRootURL = sessionsRootURL
        self.fileManager = fileManager
    }

    func threadName(for sessionID: String) -> String? {
        guard let threadID = Self.threadID(from: sessionID) else { return nil }
        refreshIfNeeded()
        return cachedNamesByID[threadID] ?? sessionMetadata(for: threadID)?.threadName
    }

    func hostApplicationName(for sessionID: String) -> String? {
        guard let threadID = Self.threadID(from: sessionID) else { return nil }
        return sessionMetadata(for: threadID)?.hostApplicationName
    }

    func indexedSessions() -> [CodexIndexedSession] {
        refreshIfNeeded()
        return cachedIndexSessionsByID.values
            .sorted { lhs, rhs in
                switch (lhs.updatedAt, rhs.updatedAt) {
                case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.order > rhs.order
                }
            }
            .map { session in
                CodexIndexedSession(
                    threadID: session.threadID,
                    threadName: session.threadName,
                    updatedAt: session.updatedAt,
                    hostApplicationName: sessionMetadata(for: session.threadID)?.hostApplicationName
                )
            }
    }

    func knownSessions() -> [CodexIndexedSession] {
        refreshIfNeeded()

        let now = Date()
        if let cachedKnownSessionsLoadedAt,
           now.timeIntervalSince(cachedKnownSessionsLoadedAt) < Self.knownSessionsCacheTTL {
            return cachedKnownSessions
        }

        var sessionsByID = Dictionary(
            uniqueKeysWithValues: indexedSessions().map { ($0.threadID, $0) }
        )
        var rolloutOnlyDisplayKeys: Set<String> = []

        for rolloutFile in rolloutSessionFiles() {
            let metadata = sessionMetadata(for: rolloutFile.threadID, fileURL: rolloutFile.url)
            if let existing = sessionsByID[rolloutFile.threadID] {
                sessionsByID[rolloutFile.threadID] = CodexIndexedSession(
                    threadID: existing.threadID,
                    threadName: existing.threadName,
                    updatedAt: existing.updatedAt ?? rolloutFile.modificationDate,
                    hostApplicationName: existing.hostApplicationName ?? metadata.hostApplicationName
                )
                continue
            }

            guard let threadName = metadata.threadName,
                  let hostApplicationName = metadata.hostApplicationName,
                  Self.isLikelyRolloutOnlySessionName(threadName)
            else {
                continue
            }

            let displayKey = "\(hostApplicationName)|\(threadName)"
            guard !rolloutOnlyDisplayKeys.contains(displayKey) else { continue }
            rolloutOnlyDisplayKeys.insert(displayKey)

            sessionsByID[rolloutFile.threadID] = CodexIndexedSession(
                threadID: rolloutFile.threadID,
                threadName: threadName,
                updatedAt: rolloutFile.modificationDate,
                hostApplicationName: hostApplicationName
            )
        }

        cachedKnownSessions = sessionsByID.values.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.threadID < rhs.threadID
            }
        }
        cachedKnownSessionsLoadedAt = now
        return cachedKnownSessions
    }

    static func threadID(from sessionID: String) -> String? {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let separatorIndex = trimmed.firstIndex(of: ":") {
            let suffix = trimmed[trimmed.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : suffix
        }

        return trimmed
    }

    static func defaultIndexURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let explicit = environment["CODEX_SESSION_INDEX_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
    }

    static func defaultSessionsRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let explicit = environment["CODEX_SESSIONS_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath, isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private func refreshIfNeeded() {
        let modificationDate = (try? fileManager.attributesOfItem(atPath: indexURL.path)[.modificationDate]) as? Date
        guard modificationDate != cachedModificationDate else { return }

        cachedModificationDate = modificationDate
        cachedIndexSessionsByID = loadIndexSessions()
        cachedNamesByID = cachedIndexSessionsByID.mapValues(\.threadName)
        cachedKnownSessionsLoadedAt = nil
        cachedKnownSessions = []
    }

    private func loadIndexSessions() -> [String: CachedIndexSession] {
        guard let data = try? Data(contentsOf: indexURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return [:]
        }

        let decoder = JSONDecoder()
        var sessionsByID: [String: CachedIndexSession] = [:]

        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            guard let lineData = String(line).data(using: .utf8),
                  let record = try? decoder.decode(IndexRecord.self, from: lineData)
            else {
                continue
            }

            let id = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let threadName = record.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !threadName.isEmpty else { continue }

            sessionsByID[id] = CachedIndexSession(
                threadID: id,
                threadName: threadName,
                updatedAt: Self.parseDate(record.updatedAt),
                order: index
            )
        }

        return sessionsByID
    }

    private func sessionMetadata(for threadID: String) -> SessionMetadata? {
        guard let fileURL = sessionFileURL(for: threadID) else { return nil }
        return sessionMetadata(for: threadID, fileURL: fileURL)
    }

    private func sessionMetadata(for threadID: String, fileURL: URL) -> SessionMetadata {
        let modificationDate = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date

        if let cached = cachedSessionMetadataByID[threadID],
           cached.fileURL == fileURL,
           cached.modificationDate == modificationDate {
            return cached.metadata
        }

        let metadata = loadSessionMetadata(from: fileURL)
        cachedSessionMetadataByID[threadID] = CachedSessionMetadata(
            fileURL: fileURL,
            modificationDate: modificationDate,
            metadata: metadata
        )
        return metadata
    }

    private func sessionFileURL(for threadID: String) -> URL? {
        rolloutSessionFiles(matching: threadID).first?.url
    }

    private func rolloutSessionFiles(matching threadID: String? = nil) -> [RolloutSessionFile] {
        let cachedFiles = currentRolloutFiles()
        if let threadID {
            return cachedRolloutFilesByThreadID[threadID] ?? []
        }
        return cachedFiles
    }

    private func currentRolloutFiles() -> [RolloutSessionFile] {
        let now = Date()
        if let cachedRolloutFilesLoadedAt,
           now.timeIntervalSince(cachedRolloutFilesLoadedAt) < Self.rolloutFilesCacheTTL {
            return cachedRolloutFiles
        }

        guard let enumerator = fileManager.enumerator(
            at: sessionsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            cachedRolloutFilesLoadedAt = now
            cachedRolloutFiles = []
            cachedRolloutFilesByThreadID = [:]
            return []
        }

        var matches: [RolloutSessionFile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  let rolloutThreadID = Self.threadID(fromRolloutFilename: url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey
                  ]),
                  values.isRegularFile == true
            else {
                continue
            }

            matches.append(
                RolloutSessionFile(
                    threadID: rolloutThreadID,
                    url: url,
                    modificationDate: values.contentModificationDate
                )
            )
        }

        cachedRolloutFiles = matches.sorted {
            ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
        }
        cachedRolloutFilesByThreadID = Dictionary(grouping: cachedRolloutFiles, by: \.threadID)
        cachedRolloutFilesLoadedAt = now
        return cachedRolloutFiles
    }

    private func loadSessionMetadata(from fileURL: URL) -> SessionMetadata {
        guard let text = readSessionMetadataText(from: fileURL) else {
            return SessionMetadata(threadName: nil, hostApplicationName: nil)
        }

        var hostApplicationName: String?
        var threadName: String?

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }

            if hostApplicationName == nil,
               let payload = object["payload"] as? [String: Any],
               (object["type"] as? String) == "session_meta" {
                hostApplicationName = Self.hostApplicationName(in: payload)
            }

            if threadName == nil,
               let candidate = Self.userPromptText(in: object),
               let displayCandidate = Self.displayPromptCandidate(from: candidate) {
                threadName = Self.compactDisplayName(displayCandidate)
            }

            if hostApplicationName != nil, threadName != nil {
                break
            }
        }

        return SessionMetadata(threadName: threadName, hostApplicationName: hostApplicationName)
    }

    private func readSessionMetadataText(from fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            try handle.seek(toOffset: 0)

            var data = try handle.read(upToCount: Int(min(fileSize, Self.maxSessionMetadataHeadBytes))) ?? Data()
            if fileSize > Self.maxSessionMetadataHeadBytes {
                let tailOffset = max(Self.maxSessionMetadataHeadBytes, fileSize - Self.maxSessionMetadataTailBytes)
                try handle.seek(toOffset: tailOffset)
                if let tailData = try handle.readToEnd(), !tailData.isEmpty {
                    data.append(0x0A)
                    data.append(tailData)
                }
            }

            return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    private static func userPromptText(in object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else { return nil }

        if (object["type"] as? String) == "event_msg",
           (payload["type"] as? String) == "user_message" {
            return stringValue(in: payload, keys: ["message", "text"])
        }

        guard (object["type"] as? String) == "response_item",
              (payload["type"] as? String) == "message",
              (payload["role"] as? String) == "user",
              let content = payload["content"] as? [[String: Any]]
        else {
            return nil
        }

        let text = content
            .compactMap { stringValue(in: $0, keys: ["text", "input_text"]) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func displayPromptCandidate(from text: String) -> String? {
        if let embeddedUserRequest = embeddedSectionText(
            in: text,
            markers: ["# User request", "## User request"]
        ) {
            return embeddedUserRequest
        }

        if let embeddedUserRequest = embeddedSectionText(
            in: text,
            markers: ["## user", "user:"]
        ) {
            return embeddedUserRequest
        }

        guard !isInjectedStartupContext(text),
              !isSyntheticPromptContext(text)
        else {
            return nil
        }

        return text
    }

    private static func embeddedSectionText(in text: String, markers: [String]) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercasedLine = trimmedLine.lowercased()
            guard let marker = markers.first(where: { marker in
                let normalizedMarker = marker.lowercased()
                return lowercasedLine == normalizedMarker
                    || lowercasedLine.hasPrefix("\(normalizedMarker):")
            }) else {
                continue
            }

            var candidateLines: [String] = []
            let markerSuffix = trimmedLine.dropFirst(marker.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
            if !markerSuffix.isEmpty {
                candidateLines.append(markerSuffix)
            }
            candidateLines.append(contentsOf: lines.dropFirst(lineIndex + 1))

            var acceptedLines: [String] = []
            for line in candidateLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if !acceptedLines.isEmpty {
                        break
                    }
                    continue
                }
                if isEmbeddedPromptWrapperLine(trimmed) {
                    if !acceptedLines.isEmpty, trimmed.hasPrefix("#") {
                        break
                    }
                    continue
                }
                acceptedLines.append(trimmed)
                if acceptedLines.count >= 3 {
                    break
                }
            }

            let candidate = acceptedLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
        }

        return nil
    }

    private static func isEmbeddedPromptWrapperLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if lowercased.hasPrefix("## context warning")
            || lowercased == "## user"
            || lowercased == "## assistant"
            || lowercased == "## assistant reply"
            || lowercased == "# user request"
            || lowercased == "## user request"
            || lowercased.hasPrefix("open design detected")
            || lowercased.hasPrefix("keep this turn compact") {
            return true
        }
        if line.hasPrefix("<")
            || line.hasPrefix("{")
            || line.hasPrefix("}")
            || line.hasPrefix("#")
            || line.hasPrefix("[")
            || line.hasPrefix("]")
            || line.hasPrefix("\"")
            || line.hasPrefix("-")
            || line.hasPrefix("(") {
            return true
        }
        return false
    }

    private static func hostApplicationName(in payload: [String: Any]) -> String? {
        let originator = stringValue(in: payload, keys: ["originator"])?.lowercased() ?? ""
        let source = stringValue(in: payload, keys: ["source", "client", "app", "application", "entrypoint", "runner"])?
            .lowercased() ?? ""
        let combined = [originator, source].joined(separator: " ")

        if containsAny(combined, tokens: ["xcode"]) {
            return "Xcode"
        }
        if containsAny(combined, tokens: ["idea", "intellij"]) {
            return "IDEA"
        }
        if containsAny(combined, tokens: ["jetbrains"]) {
            return "IDEA"
        }
        if containsAny(combined, tokens: ["visual studio code", "vscode", "vs-code"]) {
            return "VS Code"
        }
        if containsAny(combined, tokens: ["codex desktop"]) {
            return "Codex Desktop"
        }

        guard let cwd = stringValue(in: payload, keys: ["cwd"]) else { return nil }
        let components = URL(fileURLWithPath: cwd).standardizedFileURL.pathComponents
        guard let supportIndex = components.lastIndex(of: "Application Support"),
              components.indices.contains(components.index(after: supportIndex))
        else {
            return nil
        }

        return displayNameForApplicationSupportDirectory(
            components[components.index(after: supportIndex)]
        )
    }

    private static func displayNameForApplicationSupportDirectory(_ directoryName: String) -> String? {
        let trimmed = directoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "open design":
            return "OpenDesign"
        case "code":
            return "VS Code"
        case "com.apple.dt.xcode":
            return "Xcode"
        case let value where value.contains("codex"):
            return nil
        default:
            return trimmed
        }
    }

    private static func isInjectedStartupContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("# AGENTS.md instructions")
            || trimmed.hasPrefix("# Instructions (read first)")
            || trimmed.hasPrefix("<environment_context>")
            || trimmed.hasPrefix("Another language model started to solve this problem")
    }

    private static func isSyntheticPromptContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased == "message" || lowercased == "below" || lowercased == "below.)" {
            return true
        }
        return trimmed.hasPrefix("You are a memory extractor")
            || trimmed.hasPrefix("Tool results, file contents")
            || trimmed.hasPrefix("OVERRIDE")
    }

    private static func compactDisplayName(_ text: String) -> String? {
        let compacted = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compacted.isEmpty ? nil : compacted
    }

    private static func isLikelyRolloutOnlySessionName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }

        let lowercased = trimmed.lowercased()
        guard !lowercased.hasPrefix("{"),
              !lowercased.hasPrefix("["),
              !lowercased.hasPrefix("<image"),
              lowercased != "message",
              lowercased != "below.)",
              lowercased != "re"
        else {
            return false
        }

        return trimmed.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func threadID(fromRolloutFilename filename: String) -> String? {
        guard filename.hasPrefix("rollout-"),
              filename.hasSuffix(".jsonl")
        else {
            return nil
        }

        let withoutExtension = String(filename.dropLast(".jsonl".count))
        guard withoutExtension.count >= 36 else {
            return nil
        }

        let start = withoutExtension.index(withoutExtension.endIndex, offsetBy: -36)
        let threadID = String(withoutExtension[start...])
        return isUUIDLikeThreadID(threadID) ? threadID : nil
    }

    private static func isUUIDLikeThreadID(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        let hyphenOffsets: Set<Int> = [8, 13, 18, 23]

        for (offset, scalar) in value.unicodeScalars.enumerated() {
            if hyphenOffsets.contains(offset) {
                guard scalar == "-" else { return false }
                continue
            }

            guard ("0"..."9").contains(scalar)
                || ("a"..."f").contains(scalar)
                || ("A"..."F").contains(scalar)
            else {
                return false
            }
        }
        return true
    }

    private static func stringValue(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func containsAny(_ value: String, tokens: [String]) -> Bool {
        tokens.contains { value.contains($0) }
    }
}
