import Foundation

public enum MacOSBreathingStrength: String, Codable, CaseIterable, Sendable {
    case standard
    case pronounced
    case maximum

    public var displayName: String {
        switch self {
        case .standard:
            return "弱"
        case .pronounced:
            return "标准"
        case .maximum:
            return "强"
        }
    }

    var breathingAmount: Double {
        switch self {
        case .standard:
            return 0.45
        case .pronounced:
            return 0.72
        case .maximum:
            return 1.0
        }
    }
}

public enum SignalVisualStyle: Sendable {
    case trafficLight
    case macOS
}

public enum SignalVisualScale {
    public static func lampScale(
        baseScale: Double,
        intensity: Double,
        style: SignalVisualStyle,
        macOSStrength: MacOSBreathingStrength
    ) -> Double {
        guard intensity > 0 else {
            return 1
        }

        switch style {
        case .trafficLight:
            return baseScale
        case .macOS:
            return 1 - (1 - baseScale) * macOSStrength.breathingAmount
        }
    }
}
