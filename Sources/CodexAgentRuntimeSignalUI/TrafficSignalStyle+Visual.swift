import CodexAgentRuntimeSignalCore

extension TrafficSignalStyle {
    public var visualStyle: SignalVisualStyle {
        switch self {
        case .trafficLight:
            return .trafficLight
        case .macOS:
            return .macOS
        }
    }
}
