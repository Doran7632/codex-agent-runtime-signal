import Darwin
import Foundation

public enum SignalStateStoreError: Error, LocalizedError {
    case cannotCreateStateDirectory(URL, Error)
    case cannotOpenLock(String)
    case cannotAcquireLock(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateStateDirectory(let url, let error):
            return "Cannot create state directory at \(url.path): \(error.localizedDescription)"
        case .cannotOpenLock(let path):
            return "Cannot open state lock at \(path)."
        case .cannotAcquireLock(let path, let errorCode):
            return "Cannot acquire state lock at \(path): errno \(errorCode)."
        }
    }
}

public struct SignalSessionUpdate: Equatable, Sendable {
    public let signal: RuntimeSignal
    public let sessionID: String
    public let agent: String?
    public let lastEvent: String?
    public let updatedAt: Date

    public init(
        signal: RuntimeSignal,
        sessionID: String,
        agent: String? = nil,
        lastEvent: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.signal = signal
        self.sessionID = sessionID
        self.agent = agent
        self.lastEvent = lastEvent
        self.updatedAt = updatedAt
    }
}

public final class SignalStateStore: @unchecked Sendable {
    private struct FileSignature: Equatable {
        let modificationDate: Date?
        let size: UInt64
    }

    public let stateFileURL: URL
    public let sessionTTLSeconds: Double
    public let completedTTLSeconds: Double
    public let eventLimit: Int
    private static let duplicateEventWindow: TimeInterval = 4
    private static let redundantRefreshWindow: TimeInterval = 60
    private static let dateParser = LockedISO8601DateParser()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let processLock = NSLock()
    private var cachedDocument: SignalStateDocument?
    private var cachedFileSignature: FileSignature?

    public init(
        stateFileURL: URL = SignalStateStore.defaultStateFileURL(),
        sessionTTLSeconds: Double = SignalStateStore.defaultSessionTTL(),
        completedTTLSeconds: Double = SignalStateStore.defaultCompletedTTL(),
        eventLimit: Int = SignalStateStore.defaultEventLimit()
    ) {
        self.stateFileURL = stateFileURL
        self.sessionTTLSeconds = sessionTTLSeconds
        self.completedTTLSeconds = completedTTLSeconds
        self.eventLimit = eventLimit
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func defaultStateFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let explicit = nonEmptyEnvironmentValue("CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE", in: environment) {
            return URL(fileURLWithPath: explicit.expandingTildeInPath)
        }

        let stateDirectory = nonEmptyEnvironmentValue("CODEX_AGENT_RUNTIME_SIGNAL_STATE_DIR", in: environment)
            ?? nonEmptyEnvironmentValue("RUNTIME_SIGNAL_STATE_DIR", in: environment)
            ?? "/tmp/codex-agent-runtime-signal"
        return URL(fileURLWithPath: stateDirectory.expandingTildeInPath, isDirectory: true)
            .appendingPathComponent("status.json")
    }

    public static func defaultSessionTTL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Double {
        guard let rawValue = environment["RUNTIME_SIGNAL_SESSION_TTL_SECONDS"],
              let value = Double(rawValue),
              value > 0
        else {
            return 30 * 60
        }
        return value
    }

    public static func defaultCompletedTTL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Double {
        guard let rawValue = environment["CODEX_AGENT_RUNTIME_SIGNAL_COMPLETED_TTL_SECONDS"]
                ?? environment["RUNTIME_SIGNAL_COMPLETED_TTL_SECONDS"],
              let value = Double(rawValue),
              value > 0
        else {
            return 30
        }
        return value
    }

    public static func defaultEventLimit(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        guard let rawValue = environment["CODEX_AGENT_RUNTIME_SIGNAL_EVENT_LIMIT"],
              let value = Int(rawValue),
              value > 0
        else {
            return 50
        }
        return value
    }

    private static func nonEmptyEnvironmentValue(
        _ key: String,
        in environment: [String: String]
    ) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            if let date = date(fromISO8601String: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(string)"
            )
        }

        if let timestamp = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: timestamp)
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO8601 date string or UNIX timestamp"
        )
    }

    private static func date(fromISO8601String value: String) -> Date? {
        dateParser.date(from: value)
    }

    private final class LockedISO8601DateParser: @unchecked Sendable {
        private let lock = NSLock()
        private let fractionalFormatter: ISO8601DateFormatter
        private let standardFormatter: ISO8601DateFormatter
        private var cache: [String: Date] = [:]
        private var cacheOrder: [String] = []
        private let cacheLimit = 1024

        init() {
            fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
        }

        func date(from value: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            if let cachedDate = cache[value] {
                return cachedDate
            }

            let date = fractionalFormatter.date(from: value)
                ?? standardFormatter.date(from: value)
            if let date {
                cache[value] = date
                cacheOrder.append(value)
                if cacheOrder.count > cacheLimit {
                    let overflow = cacheOrder.count - cacheLimit
                    for key in cacheOrder.prefix(overflow) {
                        cache.removeValue(forKey: key)
                    }
                    cacheOrder.removeFirst(overflow)
                }
            }
            return date
        }
    }

    public func readSnapshot() -> SignalSnapshot {
        do {
            return try withStateLock {
                try readSnapshotLocked(persistingRuntimeChanges: true)
            }
        } catch {
            return readSnapshotWithoutLock()
        }
    }

    public func setManualSignal(_ signal: RuntimeSignal) throws -> SignalSnapshot {
        try withStateLock {
            let now = Date()
            var resolvedSignal = signal

            if signal == .sessionStart || signal == .sessionEnd || signal == .turnEnd {
                resolvedSignal = .idle
            }

            var document = readDocument()
            _ = pruneRuntimeSessions(in: &document, now: now)

            switch resolvedSignal.displayState {
            case .ready:
                document.sessions.removeAll()
                document.aggregate = .idle
            case .paused:
                document.sessions.removeAll()
                document.aggregate = resolvedSignal.normalizedAggregateSignal
            default:
                document.sessions["manual"] = SessionRecord(
                    agent: "manual",
                    signal: resolvedSignal,
                    lastEvent: "ManualSet",
                    updatedAt: now
                )
                document.aggregate = document.aggregateSignal()
            }

            appendEvent(
                to: &document,
                sessionID: "manual",
                agent: "manual",
                signal: resolvedSignal,
                event: "ManualSet",
                updatedAt: now
            )
            document.updatedAt = now
            try writeDocument(document)
            return document.snapshot(stateFileURL: stateFileURL)
        }
    }

    public func clearSessions() throws -> SignalSnapshot {
        try setManualSignal(.idle)
    }

    public func applySessionSignal(
        _ signal: RuntimeSignal,
        sessionID: String,
        agent: String? = nil,
        lastEvent: String? = nil,
        updatedAt: Date = Date()
    ) throws -> SignalSnapshot {
        try applySessionSignals([
            SignalSessionUpdate(
                signal: signal,
                sessionID: sessionID,
                agent: agent,
                lastEvent: lastEvent,
                updatedAt: updatedAt
            )
        ])
    }

    public func applySessionSignals(_ updates: [SignalSessionUpdate]) throws -> SignalSnapshot {
        try withStateLock {
            var document = readDocument()
            let latestSnapshotDate = updates.last?.updatedAt ?? Date()
            let now = Date()
            var didChangeDocument = false
            for update in updates {
                if applySessionUpdate(update, to: &document, now: now) {
                    didChangeDocument = true
                }
            }
            if didChangeDocument {
                compactEventHistory(in: &document)
                document.updatedAt = latestSnapshotDate
                try writeDocument(document)
            }
            return document.snapshot(stateFileURL: stateFileURL)
        }
    }

}

private extension RuntimeSignal {
    var preserveAgainstSessionEndSignal: Bool {
        switch displayState {
        case .completed, .needsReview, .permission, .blocked, .stale, .paused:
            return true
        case .ready, .active:
            return false
        }
    }

    var preserveAgainstCompletedSignal: Bool {
        switch displayState {
        case .needsReview, .permission, .blocked, .stale, .paused:
            return true
        case .ready, .active, .completed:
            return false
        }
    }
}

private extension SignalStateStore {
    struct RuntimePruneResult {
        let hadSessionsBeforePrune: Bool
        let removedNonCompletedSession: Bool
    }

    func pruneRuntimeSessions(in document: inout SignalStateDocument, now: Date) -> RuntimePruneResult {
        let previousSessions = document.sessions
        var removedNonCompletedSession = false

        document.sessions = previousSessions.filter { _, record in
            let ttlSeconds = runtimeTTLSeconds(for: record.signal)
            let shouldKeep = now.timeIntervalSince(record.updatedAt) <= ttlSeconds
            if !shouldKeep && shouldExpiredSessionMarkStateStale(record.signal) {
                removedNonCompletedSession = true
            }
            return shouldKeep
        }

        return RuntimePruneResult(
            hadSessionsBeforePrune: !previousSessions.isEmpty,
            removedNonCompletedSession: removedNonCompletedSession
        )
    }

    func runtimeTTLSeconds(for signal: RuntimeSignal) -> Double {
        switch signal {
        case .done, .toolDone, .subagentStop:
            return completedTTLSeconds
        default:
            return sessionTTLSeconds
        }
    }

    func shouldExpiredSessionMarkStateStale(_ signal: RuntimeSignal) -> Bool {
        switch signal {
        case .done, .toolDone, .subagentStop, .idle, .sessionStart, .sessionEnd, .turnEnd:
            return false
        default:
            return signal.displayState != .completed
        }
    }

    func readSnapshotLocked(persistingRuntimeChanges: Bool) throws -> SignalSnapshot {
        var document = readDocument()
        let originalDocument = document
        let now = Date()
        prepareSnapshotDocument(&document, now: now)

        if persistingRuntimeChanges && document != originalDocument {
            document.updatedAt = now
            try writeDocument(document)
        }

        return document.snapshot(stateFileURL: stateFileURL)
    }

    func readSnapshotWithoutLock() -> SignalSnapshot {
        processLock.lock()
        defer { processLock.unlock() }

        var document = readDocument()
        let originalDocument = document
        let now = Date()
        prepareSnapshotDocument(&document, now: now)
        if document != originalDocument {
            document.updatedAt = now
        }
        return document.snapshot(stateFileURL: stateFileURL)
    }

    func prepareSnapshotDocument(_ document: inout SignalStateDocument, now: Date) {
        let pruneResult = pruneRuntimeSessions(in: &document, now: now)
        compactEventHistory(in: &document)
        updateAggregateAfterPruning(in: &document, pruneResult: pruneResult)
    }

    func updateAggregateAfterPruning(
        in document: inout SignalStateDocument,
        pruneResult: RuntimePruneResult
    ) {
        if pruneResult.hadSessionsBeforePrune && document.sessions.isEmpty && document.aggregate?.displayState != .paused {
            document.aggregate = pruneResult.removedNonCompletedSession ? .stale : .idle
        } else if !document.sessions.isEmpty {
            document.aggregate = document.aggregateSignal()
        }
    }

    func shouldIgnoreOutOfOrderEvent(
        existing: SessionRecord?,
        updatedAt eventDate: Date
    ) -> Bool {
        guard let existing else { return false }
        return existing.updatedAt > eventDate
    }

    func shouldIgnoreCompletedSessionReplay(
        existing: SessionRecord?,
        signal: RuntimeSignal,
        event: String?
    ) -> Bool {
        guard existing?.signal.displayState == .completed,
              signal.displayState == .active,
              let event
        else {
            return false
        }

        switch event {
        case "DesktopActivityHeartbeat",
             "DesktopThinking",
             "DesktopMessage",
             "DesktopToolDone":
            return true
        default:
            return false
        }
    }

    func shouldIgnoreRedundantSessionRefresh(
        existing: SessionRecord?,
        signal: RuntimeSignal,
        agent: String?,
        event: String?,
        eventDate: Date
    ) -> Bool {
        guard let existing,
              existing.signal == signal,
              existing.agent == agent,
              existing.lastEvent == event,
              eventDate >= existing.updatedAt
        else {
            return false
        }

        switch signal.displayState {
        case .ready, .active:
            return eventDate.timeIntervalSince(existing.updatedAt) < Self.redundantRefreshWindow
        case .completed, .needsReview, .permission, .blocked, .stale, .paused:
            return false
        }
    }

    func appendEvent(
        to document: inout SignalStateDocument,
        sessionID: String,
        agent: String?,
        signal: RuntimeSignal,
        event: String?,
        updatedAt: Date,
        compactsHistory: Bool = true
    ) {
        let record = SignalEventRecord(
            sessionID: sessionID,
            agent: agent,
            signal: signal,
            event: event,
            updatedAt: updatedAt
        )

        removeDuplicateEvent(record, from: &document.events)
        document.events.append(
            record
        )

        if compactsHistory {
            compactEventHistory(in: &document)
        }
    }

    func applySessionUpdate(
        _ update: SignalSessionUpdate,
        to document: inout SignalStateDocument,
        now: Date
    ) -> Bool {
        let originalDocument = document
        let sessionID = update.sessionID
        let signal = update.signal
        let eventDate = update.updatedAt
        let existingBeforePrune = document.sessions[sessionID]

        if shouldIgnoreOutOfOrderEvent(existing: existingBeforePrune, updatedAt: eventDate) {
            return false
        }

        let pruneResult = pruneRuntimeSessions(in: &document, now: now)

        if shouldIgnoreCompletedSessionReplay(
            existing: document.sessions[sessionID] ?? existingBeforePrune,
            signal: signal,
            event: update.lastEvent
        ) {
            updateAggregateAfterPruning(in: &document, pruneResult: pruneResult)
            return document != originalDocument
        }

        if shouldIgnoreRedundantSessionRefresh(
            existing: document.sessions[sessionID] ?? existingBeforePrune,
            signal: signal,
            agent: update.agent,
            event: update.lastEvent,
            eventDate: eventDate
        ) {
            updateAggregateAfterPruning(in: &document, pruneResult: pruneResult)
            return document != originalDocument
        }

        switch signal {
        case .off, .pause, .paused:
            document.sessions.removeAll()
            document.aggregate = .off
        case .sessionEnd:
            let currentSignal = document.sessions[sessionID]?.signal
            if currentSignal == nil || currentSignal?.preserveAgainstSessionEndSignal == false {
                document.sessions.removeValue(forKey: sessionID)
            }
            if document.sessions.isEmpty && document.aggregate?.displayState != .paused {
                document.aggregate = .idle
            }
        case .turnEnd:
            let currentSignal = document.sessions[sessionID]?.signal
            if currentSignal == nil || currentSignal?.blocksTurnEndClear == false {
                document.sessions.removeValue(forKey: sessionID)
            }
            if document.sessions.isEmpty && document.aggregate?.displayState != .paused {
                document.aggregate = .idle
            }
        case .idle, .sessionStart:
            document.sessions[sessionID] = SessionRecord(
                agent: update.agent,
                signal: .idle,
                lastEvent: update.lastEvent,
                updatedAt: eventDate
            )
        case .done:
            if document.sessions[sessionID]?.signal.preserveAgainstCompletedSignal != true {
                document.sessions[sessionID] = SessionRecord(
                    agent: update.agent,
                    signal: signal,
                    lastEvent: update.lastEvent,
                    updatedAt: eventDate
                )
            }
        default:
            document.sessions[sessionID] = SessionRecord(
                agent: update.agent,
                signal: signal,
                lastEvent: update.lastEvent,
                updatedAt: eventDate
            )
        }

        if signal.displayState != .paused {
            document.aggregate = document.aggregateSignal()
        }
        appendEvent(
            to: &document,
            sessionID: sessionID,
            agent: update.agent,
            signal: signal,
            event: update.lastEvent,
            updatedAt: eventDate,
            compactsHistory: false
        )

        return document != originalDocument
    }

    func eventDeduplicationKey(
        sessionID: String,
        agent: String?,
        signal: RuntimeSignal,
        event: String?
    ) -> String {
        let normalizedAgent = agent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            ?? ""
        let normalizedEvent = event?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        ?? signal.rawValue

        return "\(sessionID)|\(normalizedAgent)|\(signal.rawValue)|\(normalizedEvent)"
    }

    func removeDuplicateEvent(_ event: SignalEventRecord, from events: inout [SignalEventRecord]) {
        let duplicateKey = eventDeduplicationKey(
            sessionID: event.sessionID,
            agent: event.agent,
            signal: event.signal,
            event: event.event
        )
        guard let duplicateIndex = events.lastIndex(where: { existing in
            eventDeduplicationKey(
                sessionID: existing.sessionID,
                agent: existing.agent,
                signal: existing.signal,
                event: existing.event
            ) == duplicateKey
                && abs(existing.updatedAt.timeIntervalSince(event.updatedAt)) <= Self.duplicateEventWindow
        }) else {
            return
        }

        events.remove(at: duplicateIndex)
    }

    func compactEventHistory(in document: inout SignalStateDocument) {
        var compactedReversedEvents: [SignalEventRecord] = []
        var latestKeptDateByKey: [String: Date] = [:]

        for event in document.events.reversed() {
            let key = eventDeduplicationKey(
                sessionID: event.sessionID,
                agent: event.agent,
                signal: event.signal,
                event: event.event
            )

            if let latestKeptDate = latestKeptDateByKey[key],
               abs(latestKeptDate.timeIntervalSince(event.updatedAt)) <= Self.duplicateEventWindow {
                latestKeptDateByKey[key] = event.updatedAt
                continue
            }

            latestKeptDateByKey[key] = event.updatedAt
            compactedReversedEvents.append(event)
        }

        var compactedEvents = Array(compactedReversedEvents.reversed())
        if compactedEvents.count > eventLimit {
            compactedEvents = Array(compactedEvents.suffix(eventLimit))
        }

        document.events = Array(compactedEvents)
    }

    func readDocument() -> SignalStateDocument {
        let currentSignature = fileSignature()
        if let cachedDocument,
           cachedFileSignature == currentSignature {
            return cachedDocument
        }

        guard let data = try? Data(contentsOf: stateFileURL) else {
            let document = SignalStateDocument()
            cachedDocument = document
            cachedFileSignature = nil
            return document
        }

        do {
            let document = try decoder.decode(SignalStateDocument.self, from: data)
            cachedDocument = document
            cachedFileSignature = currentSignature
            return document
        } catch {
            let document = SignalStateDocument(aggregate: .stale, updatedAt: Date())
            cachedDocument = document
            cachedFileSignature = currentSignature
            return document
        }
    }

    func writeDocument(_ document: SignalStateDocument) throws {
        let directory = stateFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw SignalStateStoreError.cannotCreateStateDirectory(directory, error)
        }

        let data = try encoder.encode(document)
        try data.write(to: stateFileURL, options: [.atomic])
        cachedDocument = document
        cachedFileSignature = fileSignature()
    }

    private func fileSignature() -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: stateFileURL.path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return FileSignature(
            modificationDate: attributes[.modificationDate] as? Date,
            size: size.uint64Value
        )
    }

    func withStateLock<T>(_ body: () throws -> T) throws -> T {
        processLock.lock()
        defer { processLock.unlock() }

        let directory = stateFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw SignalStateStoreError.cannotCreateStateDirectory(directory, error)
        }

        let lockURL = directory.appendingPathComponent("state.lock")
        let fileDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fileDescriptor >= 0 else {
            throw SignalStateStoreError.cannotOpenLock(lockURL.path)
        }

        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        while fcntl(fileDescriptor, F_SETLKW, &lock) != 0 {
            let errorCode = errno
            if errorCode == EINTR {
                continue
            }

            Darwin.close(fileDescriptor)
            throw SignalStateStoreError.cannotAcquireLock(lockURL.path, errorCode)
        }
        defer {
            var unlock = flock()
            unlock.l_type = Int16(F_UNLCK)
            unlock.l_whence = Int16(SEEK_SET)
            _ = fcntl(fileDescriptor, F_SETLK, &unlock)
            Darwin.close(fileDescriptor)
        }

        return try body()
    }
}

private extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
