import CodexAgentRuntimeSignalCore
import Foundation

enum ActivitySessionRuntimeKind {
    case desktop
    case terminal
    case ide
    case local
}

enum ActivityPresentation {
    static let currentSessionLimit = 6
    private static let liveSessionWindow: TimeInterval = 5 * 60
    private static let passiveActiveSessionWindow: TimeInterval = 45
    private static let factsCache = ActivityPresentationFactsCache()
    private static let ideIdentityTokens = [
        "codex-ide", "claude-ide", "-ide", ":ide",
        "idea", "intellij", "jetbrains",
        "vscode", "vs-code", "visual-studio-code",
        "xcode"
    ]

    private struct ActivityPresentationFacts {
        let normalizedAgentKey: String
        let runtimeKind: ActivitySessionRuntimeKind
        let sourceDetail: String?
        let activitySourceKey: String
    }

    private struct ActivityPresentationFactsKey: Hashable {
        let agent: String
        let sessionID: String
        let event: String
    }

    private final class ActivityPresentationFactsCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [ActivityPresentationFactsKey: ActivityPresentationFacts] = [:]
        private let maximumEntryCount = 512

        func facts(
            for key: ActivityPresentationFactsKey,
            build: () -> ActivityPresentationFacts
        ) -> ActivityPresentationFacts {
            lock.lock()
            if let cached = storage[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let facts = build()

            lock.lock()
            if storage.count >= maximumEntryCount {
                storage.removeAll(keepingCapacity: true)
            }
            storage[key] = facts
            lock.unlock()

            return facts
        }
    }

    static func visibleSessions(
        from snapshot: SignalSnapshot,
        now: Date = Date(),
        limit: Int? = nil
    ) -> [SessionStatus] {
        visibleSessions(from: snapshot.sessions, now: now, limit: limit)
    }

    static func visibleSessions(
        from sourceSessions: [SessionStatus],
        now: Date = Date(),
        limit: Int? = nil
    ) -> [SessionStatus] {
        let visibleSourceSessions = sourceSessions.filter { isVisibleSession($0, now: now) }
        let nonPresenceSourceKeys = Set(
            visibleSourceSessions
                .filter { !isPresenceSession($0) }
                .map(activitySourceKey(for:))
        )
        var sessionIndexes: [String: Int] = [:]
        var sessions: [SessionStatus] = []

        for session in visibleSourceSessions {
            if isPresenceSession(session),
               nonPresenceSourceKeys.contains(activitySourceKey(for: session)) {
                continue
            }

            let sessionKey = activitySessionIdentityKey(for: session)
            if let index = sessionIndexes[sessionKey] {
                if shouldPreferVisibleSession(session, over: sessions[index]) {
                    sessions[index] = session
                }
                continue
            }

            sessionIndexes[sessionKey] = sessions.count
            sessions.append(session)
        }

        let sortedSessions = sessions.sorted(by: stableSessionSortPrecedes)

        if let limit {
            return Array(sortedSessions.prefix(limit))
        }

        return sortedSessions
    }

    static func visibleRunningSessions(
        from snapshot: SignalSnapshot,
        now: Date = Date(),
        limit: Int? = nil
    ) -> [SessionStatus] {
        visibleSessions(from: snapshot, now: now, limit: limit)
            .filter(isRunningCurrentSession)
    }

    static func recentEvents(
        from snapshot: SignalSnapshot,
        excluding currentSessions: [SessionStatus],
        limit: Int? = nil
    ) -> [RecentSignalEvent] {
        let currentSessionKeys = Set(
            currentSessions.map { session in
                "\(session.sessionID)|\(session.signal.rawValue)|\(session.lastEvent ?? "")"
            }
        )
        let currentSourceEventKeys = Set(
            currentSessions.map { session in
                "\(activitySourceKey(for: session))|\(session.signal.rawValue)|\(session.lastEvent ?? "")"
            }
        )

        let filtered = snapshot.recentEvents.lazy.filter { event in
            guard !MenuBarStatusModel.isManualIdleControlEvent(event) else {
                return false
            }

            let eventKey = "\(event.sessionID)|\(event.signal.rawValue)|\(event.event ?? "")"
            let sourceEventKey = "\(activitySourceKey(for: event))|\(event.signal.rawValue)|\(event.event ?? "")"
            return !currentSessionKeys.contains(eventKey)
                && !currentSourceEventKeys.contains(sourceEventKey)
        }

        if let limit {
            return Array(filtered.prefix(limit))
        }

        return Array(filtered)
    }

    static func normalizedAgentKey(_ agent: String?, fallback: String) -> String {
        facts(agent: agent, sessionID: fallback, event: nil).normalizedAgentKey
    }

    static func activitySourceKey(for session: SessionStatus) -> String {
        facts(agent: session.agent, sessionID: session.sessionID, event: session.lastEvent).activitySourceKey
    }

    static func activitySourceKey(for event: RecentSignalEvent) -> String {
        facts(agent: event.agent, sessionID: event.sessionID, event: event.event).activitySourceKey
    }

    static func runtimeKind(for session: SessionStatus) -> ActivitySessionRuntimeKind {
        facts(agent: session.agent, sessionID: session.sessionID, event: session.lastEvent).runtimeKind
    }

    static func runtimeKind(for event: RecentSignalEvent) -> ActivitySessionRuntimeKind {
        facts(agent: event.agent, sessionID: event.sessionID, event: event.event).runtimeKind
    }

    static func sourceDetail(for session: SessionStatus) -> String? {
        facts(agent: session.agent, sessionID: session.sessionID, event: session.lastEvent).sourceDetail
    }

    static func sourceDetail(for event: RecentSignalEvent) -> String? {
        facts(agent: event.agent, sessionID: event.sessionID, event: event.event).sourceDetail
    }

    static func isCodexActivity(_ session: SessionStatus) -> Bool {
        activitySourceKey(for: session).hasPrefix("codex:")
    }

    static func activitySessionIdentityKey(for session: SessionStatus) -> String {
        if isPresenceSession(session) {
            return "presence:\(activitySourceKey(for: session))"
        }

        if session.sessionID.hasPrefix("recent-activity:") {
            return "recent:\(activitySourceKey(for: session))"
        }

        let agentKey = normalizedAgentKey(session.agent, fallback: session.sessionID)
        switch agentKey {
        case "codex", "claude":
            if let threadID = CodexThreadNameIndex.threadID(from: session.sessionID) {
                return "\(agentKey):thread:\(threadID)"
            }
            return "\(agentKey):\(activitySourceKey(for: session))"
        default:
            return "\(activitySourceKey(for: session)):\(session.sessionID)"
        }
    }

    static func stableSessionSortPrecedes(_ lhs: SessionStatus, _ rhs: SessionStatus) -> Bool {
        if lhs.signal.displayState.priority != rhs.signal.displayState.priority {
            return lhs.signal.displayState.priority > rhs.signal.displayState.priority
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        let lhsSourceKey = activitySourceKey(for: lhs)
        let rhsSourceKey = activitySourceKey(for: rhs)
        if lhsSourceKey != rhsSourceKey {
            return lhsSourceKey < rhsSourceKey
        }

        let lhsIdentityKey = activitySessionIdentityKey(for: lhs)
        let rhsIdentityKey = activitySessionIdentityKey(for: rhs)
        if lhsIdentityKey != rhsIdentityKey {
            return lhsIdentityKey < rhsIdentityKey
        }

        if lhs.sessionID != rhs.sessionID {
            return lhs.sessionID < rhs.sessionID
        }

        let lhsAgent = lhs.agent ?? ""
        let rhsAgent = rhs.agent ?? ""
        if lhsAgent != rhsAgent {
            return lhsAgent < rhsAgent
        }

        return (lhs.lastEvent ?? "") < (rhs.lastEvent ?? "")
    }

    private static func facts(agent: String?, sessionID: String, event: String?) -> ActivityPresentationFacts {
        let key = ActivityPresentationFactsKey(
            agent: agent ?? "",
            sessionID: sessionID,
            event: event ?? ""
        )
        return factsCache.facts(for: key) {
            let agentKey = uncachedNormalizedAgentKey(agent, fallback: sessionID)
            let runtime = uncachedRuntimeKind(agent: agent, sessionID: sessionID, event: event)
            let detail = uncachedSourceDetail(agent: agent, sessionID: sessionID, event: event)
            let sourceKey = uncachedActivitySourceKey(
                normalizedAgentKey: agentKey,
                runtimeKind: runtime,
                sourceDetail: detail,
                sessionID: sessionID
            )
            return ActivityPresentationFacts(
                normalizedAgentKey: agentKey,
                runtimeKind: runtime,
                sourceDetail: detail,
                activitySourceKey: sourceKey
            )
        }
    }

    private static func uncachedNormalizedAgentKey(_ agent: String?, fallback: String) -> String {
        guard let agent, !agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }

        let normalized = normalizedAgentName(agent)

        switch normalized {
        case "codex", "codex-desktop", "codex-cli", "codex-ide", "codex-xcode",
             "codex-terminal", "terminal-codex", "codex-tui", "codex-shell",
             "idea-codex", "intellij-codex", "jetbrains-codex", "codex-idea",
             "codex-intellij", "codex-jetbrains", "codex-vscode", "vscode-codex",
             "xcode-codex", "codex-obsidian", "obsidian-codex", "codex-acp":
            return "codex"
        case "claude", "claude-code", "claude-desktop", "claude-cli",
             "claude-terminal", "terminal-claude", "claude-ide",
             "idea-claude", "intellij-claude", "jetbrains-claude":
            return "claude"
        default:
            return normalized
        }
    }

    private static func uncachedSourceDetail(agent rawAgent: String?, sessionID rawSessionID: String, event rawEvent: String?) -> String? {
        let agent = normalizedAgentName(rawAgent)
        let sessionID = rawSessionID.lowercased()
        let event = (rawEvent ?? "").lowercased()

        if containsAny(agent, sessionID, event, tokens: ["obsidian"]) {
            return "Obsidian"
        }

        if containsIDEIdentity(agent, sessionID, event) {
            if containsAny(agent, sessionID, event, tokens: ["idea", "intellij"]) {
                return "IDEA"
            }
            if containsAny(agent, sessionID, event, tokens: ["jetbrains"]) {
                return "JetBrains"
            }
            if containsAny(agent, sessionID, event, tokens: ["vscode", "vs-code", "visual-studio-code"]) {
                return "VS Code"
            }
            if containsAny(agent, sessionID, event, tokens: ["xcode"]) {
                return "Xcode"
            }
            return "IDE"
        }

        return nil
    }

    private static func uncachedActivitySourceKey(
        normalizedAgentKey agentKey: String,
        runtimeKind runtime: ActivitySessionRuntimeKind,
        sourceDetail detail: String?,
        sessionID: String
    ) -> String {
        switch agentKey {
        case "codex", "claude":
            if case .ide = runtime,
               let detail {
                return "\(agentKey):ide:\(detail.lowercased().replacingOccurrences(of: " ", with: "-"))"
            }
            if let detail {
                return "\(agentKey):app:\(detail.lowercased().replacingOccurrences(of: " ", with: "-"))"
            }
            return "\(agentKey):\(runtime)"
        default:
            return "\(agentKey):\(sessionID)"
        }
    }

    private static func uncachedRuntimeKind(agent rawAgent: String?, sessionID rawSessionID: String, event rawEvent: String?) -> ActivitySessionRuntimeKind {
        let agent = normalizedAgentName(rawAgent)
        let sessionID = rawSessionID.lowercased()
        let event = (rawEvent ?? "").lowercased()

        if containsIDEIdentity(agent, sessionID, event) {
            return .ide
        }

        if agent == "claude-code" || agent == "claude"
            || agent == "claude-cli" || agent == "claude-terminal"
            || sessionID.hasPrefix("claude-cli:")
            || agent == "codex-cli" || agent == "codex-terminal"
            || agent == "codex-tui" || agent == "codex-shell"
            || agent == "codex-acp"
            || agent == "codex" || sessionID.hasPrefix("codex-cli:") {
            return .terminal
        }

        if sessionID.hasPrefix("desktop-app:")
            || sessionID.hasPrefix("codex-desktop:")
            || agent == "codex-desktop"
            || agent == "claude-desktop"
            || event.hasPrefix("desktop") {
            return .desktop
        }

        return .local
    }

    private static func containsIDEIdentity(_ values: String...) -> Bool {
        containsAny(values, tokens: ideIdentityTokens)
    }

    private static func containsAny(_ values: [String], tokens: [String]) -> Bool {
        values.contains { value in
            tokens.contains { value.contains($0) }
        }
    }

    private static func containsAny(
        _ first: String,
        _ second: String,
        _ third: String,
        tokens: [String]
    ) -> Bool {
        for token in tokens where first.contains(token) || second.contains(token) || third.contains(token) {
            return true
        }
        return false
    }

    static func statusSubtitle(
        for session: SessionStatus,
        status: String,
        friendlyEventName: (String) -> String
    ) -> String {
        guard let rawEvent = session.lastEvent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawEvent.isEmpty
        else {
            return status
        }

        let event = rawEvent.lowercased()
        guard !event.hasPrefix("platformpresence:"),
              event != "desktopapprunning"
        else {
            return status
        }

        let eventName = friendlyEventName(rawEvent)
        return eventName.isEmpty ? status : eventName
    }

    static func eventTitle(
        for event: RecentSignalEvent,
        agentName: String
    ) -> String {
        agentName
    }

    static func eventSubtitle(
        for event: RecentSignalEvent,
        status: String,
        friendlyEventName: (String) -> String
    ) -> String {
        guard let eventName = event.event?.trimmingCharacters(in: .whitespacesAndNewlines),
              !eventName.isEmpty
        else {
            return status
        }

        return friendlyEventName(eventName)
    }

    private static func isVisibleSession(_ session: SessionStatus, now: Date) -> Bool {
        if isTerminalPresenceSession(session) {
            return false
        }

        if isOpenCodexSession(session) {
            return true
        }

        if isPresenceSession(session) {
            return true
        }

        switch session.signal.displayState {
        case .active:
            return now.timeIntervalSince(session.updatedAt) <= activeSessionWindow(for: session)
        case .completed, .needsReview, .permission, .blocked, .stale:
            return true
        case .ready, .paused:
            return false
        }
    }

    private static func isRunningCurrentSession(_ session: SessionStatus) -> Bool {
        switch session.signal.displayState {
        case .active, .completed, .needsReview, .permission, .blocked, .stale:
            return true
        case .ready, .paused:
            return false
        }
    }

    private static func shouldPreferVisibleSession(_ candidate: SessionStatus, over current: SessionStatus) -> Bool {
        let candidateIsPresence = isPresenceSession(candidate)
        let currentIsPresence = isPresenceSession(current)
        if candidateIsPresence != currentIsPresence {
            if candidateIsPresence {
                return shouldPresenceOverrideStaleActivity(candidate, nonPresence: current)
            }
            if currentIsPresence {
                return !shouldPresenceOverrideStaleActivity(current, nonPresence: candidate)
            }
        }

        let candidateIsAlert = isPersistentAlert(candidate.signal.displayState)
        let currentIsAlert = isPersistentAlert(current.signal.displayState)
        if candidateIsAlert || currentIsAlert {
            let candidatePriority = candidate.signal.displayState.priority
            let currentPriority = current.signal.displayState.priority
            if candidatePriority != currentPriority {
                return candidatePriority > currentPriority
            }
        }

        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }

        let candidateSignalPriority = activeSignalPriority(candidate.signal)
        let currentSignalPriority = activeSignalPriority(current.signal)
        if candidateSignalPriority != currentSignalPriority {
            return candidateSignalPriority > currentSignalPriority
        }

        return candidate.signal.displayState.priority > current.signal.displayState.priority
    }

    private static func shouldPresenceOverrideStaleActivity(
        _ presence: SessionStatus,
        nonPresence: SessionStatus
    ) -> Bool {
        guard nonPresence.signal.displayState == .active else {
            return false
        }

        return presence.updatedAt.timeIntervalSince(nonPresence.updatedAt) > activeSessionWindow(for: nonPresence)
    }

    private static func activeSessionWindow(for session: SessionStatus) -> TimeInterval {
        isPassiveActiveSession(session) ? passiveActiveSessionWindow : liveSessionWindow
    }

    private static func isPassiveActiveSession(_ session: SessionStatus) -> Bool {
        guard session.signal.displayState == .active else { return false }

        switch session.lastEvent {
        case "DesktopActivityHeartbeat", "DesktopThinking":
            return true
        default:
            return false
        }
    }

    private static func isPersistentAlert(_ displayState: DisplayState) -> Bool {
        switch displayState {
        case .needsReview, .permission, .blocked, .stale, .paused:
            return true
        case .ready, .active, .completed:
            return false
        }
    }

    private static func activeSignalPriority(_ signal: RuntimeSignal) -> Int {
        switch signal {
        case .working, .subagentStart:
            return 50
        case .toolDone, .subagentStop:
            return 40
        case .thinking:
            return 30
        case .done:
            return 20
        case .idle:
            return 0
        default:
            return signal.displayState.priority
        }
    }

    private static func isPresenceSession(_ session: SessionStatus) -> Bool {
        session.sessionID.hasPrefix("desktop-app:")
            || session.sessionID.hasPrefix("platform-presence:")
            || session.lastEvent == "DesktopAppRunning"
            || session.lastEvent?.hasPrefix("PlatformPresence:") == true
    }

    static func isOpenCodexSession(_ session: SessionStatus) -> Bool {
        session.lastEvent == "CodexSessionOpen"
            && isCodexActivity(session)
            && CodexThreadNameIndex.threadID(from: session.sessionID) != nil
    }

    static func isDiscoveredCodexIdleSession(_ session: SessionStatus) -> Bool {
        isOpenCodexSession(session)
    }

    static func isTerminalPresenceSession(_ session: SessionStatus) -> Bool {
        session.sessionID == "platform-presence:codex-cli"
            || session.lastEvent == "PlatformPresence:CLI"
    }

    private static func normalizedAgentName(_ agent: String?) -> String {
        guard let agent else { return "" }
        return agent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

extension MenuBarStatusModel {
    func activitySessionTitle(for session: SessionStatus) -> String {
        "\(friendlyAgentName(session.agent)) · \(activitySessionRuntimeLabel(for: session))"
    }

    func activitySessionLine(for session: SessionStatus) -> String {
        "\(activitySessionSourceTitle(for: session)) - \(activitySessionLineStatus(for: session)) - (\(activitySessionName(for: session)))"
    }

    func activitySessionSourceTitle(for session: SessionStatus) -> String {
        if ActivityPresentation.isCodexActivity(session),
           let hostApplicationName = codexThreadNameResolver.hostApplicationName(for: session.sessionID) {
            return hostApplicationName
        }
        if ActivityPresentation.isCodexActivity(session),
           let sourceDetail = ActivityPresentation.sourceDetail(for: session) {
            return sourceDetail
        }

        switch ActivityPresentation.runtimeKind(for: session) {
        case .desktop:
            if ActivityPresentation.activitySourceKey(for: session).hasPrefix("codex:") {
                return "Codex Desktop"
            }
            if ActivityPresentation.activitySourceKey(for: session).hasPrefix("claude:") {
                return "Claude Desktop"
            }
            return text("桌面版", "Desktop")
        case .terminal:
            return text("桌面终端", "Desktop Terminal")
        case .ide:
            return ActivityPresentation.sourceDetail(for: session) ?? "IDE"
        case .local:
            return friendlyAgentName(session.agent)
        }
    }

    func activitySessionName(for session: SessionStatus) -> String {
        if ActivityPresentation.isCodexActivity(session),
           let threadName = codexThreadNameResolver.threadName(for: session.sessionID) {
            return threadName
        }

        if ActivityPresentation.isCodexActivity(session) {
            return text("未命名会话", "Unnamed session")
        }

        return shortenedSessionID(session.sessionID)
    }

    func activitySessionLineStatus(for session: SessionStatus) -> String {
        switch session.signal.displayState {
        case .active:
            return text("运行中", "Running")
        case .ready:
            return text("空闲", "Idle")
        case .completed:
            return text("空闲", "Idle")
        case .needsReview, .permission, .blocked, .stale, .paused:
            return displayName(for: session.signal)
        }
    }

    func activitySessionRuntimeLabel(for session: SessionStatus) -> String {
        switch ActivityPresentation.runtimeKind(for: session) {
        case .desktop:
            return text("桌面版运行中", "Desktop running")
        case .terminal:
            return text("终端运行中", "Terminal running")
        case .ide:
            if let detail = ActivityPresentation.sourceDetail(for: session) {
                return text("\(detail) 运行中", "\(detail) running")
            }
            return text("IDE 运行中", "IDE running")
        case .local:
            return text("本地运行中", "Local running")
        }
    }

    func activitySessionStatusSubtitle(for session: SessionStatus) -> String {
        ActivityPresentation.statusSubtitle(
            for: session,
            status: displayName(for: session.signal),
            friendlyEventName: friendlyEventName
        )
    }

    func activityEventTitle(for event: RecentSignalEvent) -> String {
        ActivityPresentation.eventTitle(
            for: event,
            agentName: activityEventAgentTitle(for: event)
        )
    }

    func activityEventSubtitle(for event: RecentSignalEvent) -> String {
        ActivityPresentation.eventSubtitle(
            for: event,
            status: displayName(for: event.signal),
            friendlyEventName: friendlyEventName
        )
    }

    private func activityEventAgentTitle(for event: RecentSignalEvent) -> String {
        let baseName = friendlyAgentName(event.agent)

        switch ActivityPresentation.runtimeKind(for: event) {
        case .desktop:
            return "\(baseName) Desktop"
        case .terminal:
            return "\(baseName) CLI"
        case .ide:
            if let detail = ActivityPresentation.sourceDetail(for: event) {
                return "\(baseName) \(detail)"
            }
            return "\(baseName) IDE"
        case .local:
            return baseName
        }
    }

    private func shortenedSessionID(_ sessionID: String) -> String {
        let rawIdentifier = CodexThreadNameIndex.threadID(from: sessionID) ?? sessionID
        guard rawIdentifier.count > 16 else { return rawIdentifier }

        return "\(rawIdentifier.prefix(8))...\(rawIdentifier.suffix(4))"
    }
}
