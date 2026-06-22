public enum ActiveSignalEffect: String, CaseIterable, Sendable {
    case greenBreathing = "green_breathing"
    case greenSteady = "green_steady"
    case greenSlowFlash = "green_slow_flash"
    case greenFastFlash = "green_fast_flash"
    case trafficCycle = "traffic_cycle"
}

public enum CompletedSignalEffect: String, CaseIterable, Sendable {
    case greenPulse = "green_pulse"
    case greenSteady = "green_steady"
    case yellowPulse = "yellow_pulse"
    case yellowSteady = "yellow_steady"
    case allSteady = "all_steady"
    case allPulse = "all_pulse"
}

public enum SignalEffectSpeed: String, CaseIterable, Sendable {
    case slow
    case standard
    case fast
}

public struct SignalEffectCustomization: Equatable, Sendable {
    public var thinkingEffect: ActiveSignalEffect
    public var activeEffect: ActiveSignalEffect
    public var activeSpeed: SignalEffectSpeed
    public var alertSpeed: SignalEffectSpeed
    public var completedEffect: CompletedSignalEffect

    public init(
        thinkingEffect: ActiveSignalEffect = .greenFastFlash,
        activeEffect: ActiveSignalEffect = .greenSlowFlash,
        activeSpeed: SignalEffectSpeed = .standard,
        alertSpeed: SignalEffectSpeed = .standard,
        completedEffect: CompletedSignalEffect = .greenSteady
    ) {
        self.thinkingEffect = thinkingEffect
        self.activeEffect = activeEffect
        self.activeSpeed = activeSpeed
        self.alertSpeed = alertSpeed
        self.completedEffect = completedEffect
    }

    public static let `default` = SignalEffectCustomization()
}
