import CodexAgentRuntimeSignalCore
import AppKit
import Foundation

final class CodexPlatformPresenceMonitor: @unchecked Sendable {
    private struct ComputerUseTurnRecord: Decodable {
        let threadID: String
        let cwd: String?
        let client: String?
        let inputMessages: [String]?

        private enum CodingKeys: String, CodingKey {
            case threadID = "thread-id"
            case cwd
            case client
            case inputMessages = "input-messages"
        }
    }

    struct RunningApplicationInfo: Equatable, Sendable {
        let bundleIdentifier: String?
        let localizedName: String?
    }

    struct RunningProcessInfo: Equatable, Sendable {
        let pid: Int?
        let ppid: Int?
        let status: String?
        let tty: String?
        let command: String
        let arguments: String

        init(
            pid: Int?,
            ppid: Int? = nil,
            status: String? = nil,
            tty: String? = nil,
            command: String,
            arguments: String
        ) {
            self.pid = pid
            self.ppid = ppid
            self.status = status
            self.tty = tty
            self.command = command
            self.arguments = arguments
        }
    }

    private struct PlatformDefinition: Sendable {
        let sessionID: String
        let agent: String
        let event: String
        let appBundleIdentifiers: Set<String>
        let appNameTokens: Set<String>
        let processMatch: @Sendable (RunningProcessInfo) -> Bool
    }

    private static let processScanTimeoutSeconds: TimeInterval = 0.7
    private static let targetedProcessScanTimeoutSeconds: TimeInterval = 0.3
    private static let openFileScanTimeoutSeconds: TimeInterval = 1.2
    private let processScanInterval: TimeInterval
    private let processCacheLock = NSLock()
    private var cachedProcesses: [RunningProcessInfo] = []
    private var lastProcessScanAt: Date?

    init(processScanInterval: TimeInterval = 20) {
        self.processScanInterval = max(processScanInterval, 0)
    }

    func detectSessions(now: Date = Date()) -> [SessionStatus] {
        Self.detectSessions(
            applications: NSWorkspace.shared.runningApplications.map {
                RunningApplicationInfo(
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.localizedName
                )
            },
            processes: runningProcesses(now: now),
            now: now
        )
    }

    static func detectSessions(
        applications: [RunningApplicationInfo],
        processes: [RunningProcessInfo],
        now: Date = Date()
    ) -> [SessionStatus] {
        definitions.compactMap { definition in
            let isRunning =
                appIsRunning(definition, applications: applications)
                || processes.contains(where: definition.processMatch)

            guard isRunning else { return nil }
            return SessionStatus(
                sessionID: definition.sessionID,
                signal: .idle,
                updatedAt: now,
                agent: definition.agent,
                lastEvent: definition.event
            )
        } + detectOpenCodexSessions(processes: processes, now: now)
    }

    private static let definitions: [PlatformDefinition] = [
        PlatformDefinition(
            sessionID: "platform-presence:codex-desktop",
            agent: "codex-desktop",
            event: "PlatformPresence:Desktop",
            appBundleIdentifiers: ["com.openai.codex"],
            appNameTokens: ["codex"],
            processMatch: { process in
                let commandLine = process.commandLine
                return commandLine.contains("/applications/codex.app/")
                    && commandLine.contains("/contents/macos/codex")
            }
        ),
        PlatformDefinition(
            sessionID: "platform-presence:codex-cli",
            agent: "codex-cli",
            event: "PlatformPresence:CLI",
            appBundleIdentifiers: [],
            appNameTokens: [],
            processMatch: { process in
                process.looksLikeCodexCLI
            }
        ),
        PlatformDefinition(
            sessionID: "platform-presence:codex-vscode",
            agent: "codex-vscode",
            event: "PlatformPresence:VSCode",
            appBundleIdentifiers: [],
            appNameTokens: [],
            processMatch: { process in
                let commandLine = process.commandLine
                return commandLine.contains("/openai.chatgpt/")
                    || (
                        commandLine.contains("/.vscode/extensions/")
                        && commandLine.contains("codex")
                    )
            }
        ),
        PlatformDefinition(
            sessionID: "platform-presence:codex-xcode",
            agent: "codex-xcode",
            event: "PlatformPresence:Xcode",
            appBundleIdentifiers: [],
            appNameTokens: [],
            processMatch: { process in
                let commandLine = process.commandLine
                return commandLine.contains("/library/developer/xcode/codingassistant/")
                    || commandLine.contains("/codingassistant/agents/")
            }
        ),
        PlatformDefinition(
            sessionID: "platform-presence:codex-idea",
            agent: "codex-idea",
            event: "PlatformPresence:IDEA",
            appBundleIdentifiers: [],
            appNameTokens: [],
            processMatch: { process in
                let commandLine = process.commandLine
                return commandLine.contains("/library/caches/jetbrains/")
                    && commandLine.contains("/aia/codex/")
            }
        ),
        PlatformDefinition(
            sessionID: "platform-presence:claude-desktop",
            agent: "claude-desktop",
            event: "PlatformPresence:Desktop",
            appBundleIdentifiers: [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude"
            ],
            appNameTokens: ["claude"],
            processMatch: { process in
                let commandLine = process.commandLine
                return commandLine.contains("/applications/claude.app/")
                    && commandLine.contains("/contents/macos/claude")
            }
        )
    ]

    private static func appIsRunning(
        _ definition: PlatformDefinition,
        applications: [RunningApplicationInfo]
    ) -> Bool {
        applications.contains { application in
            if let bundleIdentifier = normalized(application.bundleIdentifier),
               definition.appBundleIdentifiers.contains(bundleIdentifier) {
                return true
            }

            guard let localizedName = normalized(application.localizedName) else {
                return false
            }

            return definition.appNameTokens.contains(localizedName)
        }
    }

    private static func runningProcesses() -> [RunningProcessInfo] {
        runningTargetedCodexProcessGraph()
    }

    private static func runningTargetedCodexProcessGraph() -> [RunningProcessInfo] {
        let candidatePIDs = runningCodexProcessIDs()
        guard !candidatePIDs.isEmpty else { return [] }

        var requestedPIDs = candidatePIDs
        var processesByPID: [Int: RunningProcessInfo] = [:]

        for _ in 0..<16 {
            let missingPIDs = requestedPIDs.subtracting(processesByPID.keys)
            guard !missingPIDs.isEmpty else { break }

            let processes = processDetails(for: missingPIDs)
            guard !processes.isEmpty else { break }

            for process in processes {
                guard let pid = process.pid else { continue }
                processesByPID[pid] = process
                if let ppid = process.ppid, ppid > 1 {
                    requestedPIDs.insert(ppid)
                }
            }
        }

        return processesByPID.values.sorted {
            ($0.pid ?? 0) < ($1.pid ?? 0)
        }
    }

    private static func runningCodexProcessIDs() -> Set<Int> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "codex|codex-acp"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + targetedProcessScanTimeoutSeconds) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.1)
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return Set(output.split(whereSeparator: \.isNewline).compactMap { Int($0) })
    }

    private static func processDetails(for processIDs: Set<Int>) -> [RunningProcessInfo] {
        guard !processIDs.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "-o",
            "pid=,ppid=,stat=,tty=,comm=,args=",
            "-p",
            processIDs.sorted().map(String.init).joined(separator: ",")
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-agent-runtime-signal-targeted-ps-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL)
        else {
            return []
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let errorPipe = Pipe()
        process.standardOutput = outputHandle
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return []
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + targetedProcessScanTimeoutSeconds) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.1)
            return []
        }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return parseProcesses(from: output)
    }

    private static func runningAllProcesses() -> [RunningProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,stat=,tty=,comm=,args="]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-agent-runtime-signal-ps-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL)
        else {
            return []
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let errorPipe = Pipe()
        process.standardOutput = outputHandle
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return []
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + processScanTimeoutSeconds) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.2)
            return []
        }

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseProcesses(from: output)
    }

    private func runningProcesses(now: Date) -> [RunningProcessInfo] {
        processCacheLock.lock()
        if let lastProcessScanAt,
           now.timeIntervalSince(lastProcessScanAt) < processScanInterval {
            let processes = cachedProcesses
            processCacheLock.unlock()
            return processes
        }
        processCacheLock.unlock()

        let processes = Self.runningProcesses()

        processCacheLock.lock()
        cachedProcesses = processes
        lastProcessScanAt = now
        processCacheLock.unlock()

        return processes
    }

    static func parseProcesses(from output: String) -> [RunningProcessInfo] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RunningProcessInfo? in
                let parts = line.split(
                    separator: " ",
                    maxSplits: 5,
                    omittingEmptySubsequences: true
                )
                guard parts.count >= 2 else { return nil }

                if parts.count >= 5,
                   let pid = Int(parts[0]),
                   let ppid = Int(parts[1]) {
                    return RunningProcessInfo(
                        pid: pid,
                        ppid: ppid,
                        status: String(parts[2]),
                        tty: String(parts[3]),
                        command: String(parts[4]).trimmingCharacters(in: .whitespacesAndNewlines),
                        arguments: parts.count >= 6
                            ? String(parts[5]).trimmingCharacters(in: .whitespacesAndNewlines)
                            : ""
                    )
                }

                let legacyParts = line.split(
                    separator: " ",
                    maxSplits: 2,
                    omittingEmptySubsequences: true
                )
                guard legacyParts.count >= 2 else { return nil }

                return RunningProcessInfo(
                    pid: Int(legacyParts[0]),
                    command: String(legacyParts[1]).trimmingCharacters(in: .whitespacesAndNewlines),
                    arguments: legacyParts.count >= 3
                        ? String(legacyParts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                        : ""
                )
            }
    }

    private static func detectOpenCodexSessions(
        processes: [RunningProcessInfo],
        now: Date
    ) -> [SessionStatus] {
        let codexProcesses = processes.filter(\.looksLikeOpenCodexSessionProcess)
        let processIDs = codexProcesses.compactMap(\.pid)
        let openRolloutFilesByPID = processIDs.isEmpty
            ? [:]
            : runningOpenRolloutFiles(for: processIDs)

        let rolloutSessions = detectOpenCodexSessions(
            processes: processes,
            openRolloutFilesByPID: openRolloutFilesByPID,
            now: now
        )
        return mergeDiscoveredSessions(rolloutSessions)
    }

    static func detectOpenCodexSessions(
        processes: [RunningProcessInfo],
        openRolloutFilesByPID: [Int: String],
        now: Date
    ) -> [SessionStatus] {
        let processByPID = Dictionary(
            uniqueKeysWithValues: processes.compactMap { process in
                process.pid.map { ($0, process) }
            }
        )
        var sessionsByThreadID: [String: SessionStatus] = [:]

        for (pid, rolloutFile) in openRolloutFilesByPID {
            guard let threadID = threadID(fromRolloutPath: rolloutFile),
                  let process = processByPID[pid]
            else {
                continue
            }

            let agent = inferredCodexAgent(for: process, processByPID: processByPID)
            let session = SessionStatus(
                sessionID: "\(agent):\(threadID)",
                signal: .idle,
                updatedAt: now,
                agent: agent,
                lastEvent: "CodexSessionOpen"
            )

            if let current = sessionsByThreadID[threadID],
               !shouldPreferDiscoveredSession(session, over: current) {
                continue
            }
            sessionsByThreadID[threadID] = session
        }

        return sessionsByThreadID.values.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.sessionID < $1.sessionID
        }
    }

    private static func detectComputerUseOpenCodexSessions(
        processes: [RunningProcessInfo],
        now: Date
    ) -> [SessionStatus] {
        var latestOpenDesignSession: (pid: Int, session: SessionStatus)?

        for process in processes where process.looksLikeComputerUseTurnEndedProcess {
            guard let record = computerUseTurnRecord(in: process.arguments),
                  !isSyntheticComputerUseTurn(record),
                  isOpenDesignComputerUseTurn(record),
                  let pid = process.pid
            else {
                continue
            }

            let session = SessionStatus(
                sessionID: "codex-cli:\(record.threadID)",
                signal: .idle,
                updatedAt: now,
                agent: "codex-cli",
                lastEvent: "CodexSessionOpen"
            )
            if let current = latestOpenDesignSession,
               current.pid > pid {
                continue
            }
            latestOpenDesignSession = (pid, session)
        }

        if let latestOpenDesignSession {
            return [latestOpenDesignSession.session]
        }
        return []
    }

    private static func isOpenDesignComputerUseTurn(_ record: ComputerUseTurnRecord) -> Bool {
        let combined = [record.client, record.cwd]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return containsAny(combined, tokens: ["open design", "opendesign", "codex_exec"])
    }

    private static func mergeDiscoveredSessions(_ sessions: [SessionStatus]) -> [SessionStatus] {
        var sessionsByThreadID: [String: SessionStatus] = [:]

        for session in sessions {
            guard let threadID = CodexThreadNameIndex.threadID(from: session.sessionID) else {
                continue
            }

            if let current = sessionsByThreadID[threadID],
               !shouldPreferDiscoveredSession(session, over: current) {
                continue
            }
            sessionsByThreadID[threadID] = session
        }

        return sessionsByThreadID.values.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.sessionID < $1.sessionID
        }
    }

    private static func computerUseTurnRecord(in arguments: String) -> ComputerUseTurnRecord? {
        guard let jsonStart = arguments.range(of: "{")?.lowerBound else { return nil }
        let json = String(arguments[jsonStart...])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ComputerUseTurnRecord.self, from: data)
    }

    private static func isSyntheticComputerUseTurn(_ record: ComputerUseTurnRecord) -> Bool {
        guard let firstMessage = record.inputMessages?.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }

        return firstMessage.hasPrefix("you are a memory extractor")
    }


    private static func runningOpenRolloutFiles(for processIDs: [Int]) -> [Int: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-nP",
            "-p",
            processIDs.map(String.init).joined(separator: ",")
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-agent-runtime-signal-lsof-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL)
        else {
            return [:]
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let errorPipe = Pipe()
        process.standardOutput = outputHandle
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return [:]
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + openFileScanTimeoutSeconds) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.2)
            return [:]
        }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let parsed = parseOpenRolloutFiles(from: output)
        if process.terminationStatus != 0, parsed.isEmpty {
            return [:]
        }
        return parsed
    }

    static func parseOpenRolloutFiles(from output: String) -> [Int: String] {
        var filesByPID: [Int: String] = [:]

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.contains("/.codex/sessions/"),
                  line.contains("/rollout-"),
                  line.contains(".jsonl")
            else {
                continue
            }

            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int(parts[1]),
                  let pathStart = line.range(of: "/")
            else {
                continue
            }

            let path = String(line[pathStart.lowerBound...])
            guard threadID(fromRolloutPath: path) != nil else { continue }
            filesByPID[pid] = path
        }

        return filesByPID
    }

    private static func threadID(fromRolloutPath path: String) -> String? {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        guard filename.hasPrefix("rollout-"),
              filename.hasSuffix(".jsonl")
        else {
            return nil
        }

        let withoutExtension = String(filename.dropLast(".jsonl".count))
        guard let threadIDStart = withoutExtension.range(
            of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) else {
            return nil
        }

        return String(withoutExtension[threadIDStart.lowerBound...])
    }

    private static func inferredCodexAgent(
        for process: RunningProcessInfo,
        processByPID: [Int: RunningProcessInfo]
    ) -> String {
        let ancestry = processAncestry(for: process, processByPID: processByPID)
            .map(\.commandLine)
            .joined(separator: " ")

        if containsAny(ancestry, tokens: ["intellij idea.app", "idea.app", "jetbrains", "intellij"]) {
            return "codex-idea"
        }
        if containsAny(ancestry, tokens: [
            "visual studio code.app",
            "code helper",
            ".vscode",
            "openai.chatgpt",
            "vscode"
        ]) {
            return "codex-vscode"
        }
        if containsAny(ancestry, tokens: ["xcode.app", "codingassistant"]) {
            return "codex-xcode"
        }
        if containsAny(ancestry, tokens: ["obsidian.app", "obsidian helper", "application support/obsidian"]) {
            return "codex-obsidian"
        }
        if containsAny(ancestry, tokens: ["/applications/codex.app/", "codex desktop"]) {
            return "codex-desktop"
        }
        return "codex-cli"
    }

    private static func processAncestry(
        for process: RunningProcessInfo,
        processByPID: [Int: RunningProcessInfo]
    ) -> [RunningProcessInfo] {
        var ancestry: [RunningProcessInfo] = [process]
        var seenPIDs: Set<Int> = []
        var current = process

        while let parentPID = current.ppid,
              parentPID > 1,
              !seenPIDs.contains(parentPID),
              let parent = processByPID[parentPID],
              ancestry.count < 16 {
            seenPIDs.insert(parentPID)
            ancestry.append(parent)
            current = parent
        }

        return ancestry
    }

    private static func shouldPreferDiscoveredSession(
        _ candidate: SessionStatus,
        over current: SessionStatus
    ) -> Bool {
        discoveredAgentPriority(candidate.agent) > discoveredAgentPriority(current.agent)
    }

    private static func discoveredAgentPriority(_ agent: String?) -> Int {
        switch agent {
        case "codex-idea", "codex-vscode", "codex-xcode", "codex-obsidian", "codex-desktop":
            return 10
        default:
            return 0
        }
    }

    private static func containsAny(_ value: String, tokens: [String]) -> Bool {
        tokens.contains { value.contains($0) }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

private extension CodexPlatformPresenceMonitor.RunningProcessInfo {
    var commandLine: String {
        "\(command) \(arguments)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var looksLikeCodexCLI: Bool {
        let commandName = URL(fileURLWithPath: command).lastPathComponent.lowercased()
        let commandLine = commandLine
        let firstArgumentName = arguments
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { URL(fileURLWithPath: String($0)).lastPathComponent.lowercased() }

        let looksLikeCodexExecutable =
            commandName == "codex"
            || commandName == "codex-acp"
            || firstArgumentName == "codex"
            || firstArgumentName == "codex-acp"
            || commandLine == "codex"
            || commandLine.hasPrefix("codex ")
            || commandLine.contains("/codex-acp")
            || commandLine.contains("/bin/codex ")
            || commandLine.contains("/node_modules/.bin/codex")
            || commandLine.contains("/@openai/codex/")

        guard looksLikeCodexExecutable else {
            return false
        }

        guard !commandLine.contains("app-server"),
              !commandLine.contains("/applications/codex.app/"),
              !commandLine.contains("codex computer use.app"),
              !commandLine.contains("skycomputeruseclient"),
              !commandLine.contains("codexbar"),
              !commandLine.contains("/library/developer/xcode/codingassistant/"),
              !commandLine.contains("/library/caches/jetbrains/"),
              !commandLine.contains("/.vscode/extensions/"),
              !commandLine.contains("/openai.chatgpt/")
        else {
            return false
        }

        return true
    }

    var looksLikeCodexAppServer: Bool {
        let commandLine = commandLine
        guard commandLine.contains("app-server"),
              commandLine.contains("codex")
        else {
            return false
        }

        return commandLine.contains("/openai.chatgpt/")
            || commandLine.contains("/.vscode/extensions/")
            || commandLine.contains("/library/developer/xcode/codingassistant/")
            || commandLine.contains("/library/caches/jetbrains/")
            || commandLine.contains("/applications/codex.app/")
    }

    var looksLikeOpenCodexSessionProcess: Bool {
        looksLikeCodexCLI || looksLikeCodexAppServer
    }

    var looksLikeComputerUseTurnEndedProcess: Bool {
        let commandLine = commandLine
        return commandLine.contains("skycomputeruseclient")
            && commandLine.contains("turn-ended")
            && commandLine.contains("\"thread-id\"")
    }
}
