import Foundation

public struct SessionStatus: Identifiable, Equatable, Sendable {
    public var id: String { sessionID }

    public let sessionID: String
    public let signal: RuntimeSignal
    public let updatedAt: Date
    public let agent: String?
    public let lastEvent: String?

    public init(
        sessionID: String,
        signal: RuntimeSignal,
        updatedAt: Date,
        agent: String? = nil,
        lastEvent: String? = nil
    ) {
        self.sessionID = sessionID
        self.signal = signal
        self.updatedAt = updatedAt
        self.agent = agent
        self.lastEvent = lastEvent
    }
}

public struct RecentSignalEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let signal: RuntimeSignal
    public let updatedAt: Date
    public let agent: String?
    public let event: String?

    public init(
        id: String,
        sessionID: String,
        signal: RuntimeSignal,
        updatedAt: Date,
        agent: String? = nil,
        event: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.signal = signal
        self.updatedAt = updatedAt
        self.agent = agent
        self.event = event
    }
}

public struct SignalSnapshot: Equatable, Sendable {
    public let aggregate: RuntimeSignal
    public let sessions: [SessionStatus]
    public let recentEvents: [RecentSignalEvent]
    public let stateFileURL: URL
    public let updatedAt: Date?

    public init(
        aggregate: RuntimeSignal,
        sessions: [SessionStatus],
        recentEvents: [RecentSignalEvent] = [],
        stateFileURL: URL,
        updatedAt: Date? = nil
    ) {
        self.aggregate = aggregate
        self.sessions = sessions
        self.recentEvents = recentEvents
        self.stateFileURL = stateFileURL
        self.updatedAt = updatedAt
    }

    public static func idle(stateFileURL: URL) -> SignalSnapshot {
        SignalSnapshot(
            aggregate: .idle,
            sessions: [],
            recentEvents: [],
            stateFileURL: stateFileURL,
            updatedAt: nil
        )
    }
}
