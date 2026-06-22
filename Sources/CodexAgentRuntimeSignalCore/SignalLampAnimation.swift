public enum SignalLampColor: CaseIterable, Sendable {
    case red
    case yellow
    case green
}

public enum SignalLampAnimation {
    public static func intensity(
        _ color: SignalLampColor,
        signal: RuntimeSignal,
        tick: Int,
        allLightsOn: Bool = false,
        customization: SignalEffectCustomization = .default
    ) -> Double {
        if allLightsOn {
            return 1
        }

        switch signal.displayState {
        case .ready:
            return color == .green ? 1 : 0
        case .active:
            return activeIntensity(color, signal: signal, tick: tick, customization: customization)
        case .completed:
            return completedIntensity(color, tick: tick, customization: customization)
        case .needsReview:
            guard color == .yellow else { return 0 }
            let values: [Double] = [0.45, 0.72, 1.0, 0.72, 0, 0, 0, 0]
            return values[adjustedTick(tick, speed: customization.alertSpeed) % values.count]
        case .permission:
            guard color == .red else { return 0 }
            let values: [Double] = [0.45, 0.72, 1.0, 0.72, 0, 0, 0, 0]
            return values[adjustedTick(tick, speed: customization.alertSpeed) % values.count]
        case .blocked:
            return color == .red && blockedTick(tick, speed: customization.alertSpeed) % 2 == 0 ? 1 : 0
        case .stale:
            guard color == .yellow else { return 0 }
            let values: [Double] = [0.35, 0.5, 0.65, 0.5, 0, 0, 0, 0]
            return values[adjustedTick(tick, speed: customization.alertSpeed) % values.count]
        case .paused:
            return 0
        }
    }

    public static func scale(
        _ color: SignalLampColor,
        signal: RuntimeSignal,
        tick: Int,
        allLightsOn: Bool = false,
        customization: SignalEffectCustomization = .default
    ) -> Double {
        let intensity = intensity(
            color,
            signal: signal,
            tick: tick,
            allLightsOn: allLightsOn,
            customization: customization
        )
        guard intensity > 0 else {
            return 1
        }

        switch signal.displayState {
        case .active, .completed, .needsReview, .permission, .stale:
            return 0.48 + intensity * 0.52
        case .ready, .blocked, .paused:
            return 1
        }
    }

    public static func isLit(
        _ color: SignalLampColor,
        signal: RuntimeSignal,
        tick: Int,
        allLightsOn: Bool = false,
        customization: SignalEffectCustomization = .default
    ) -> Bool {
        intensity(
            color,
            signal: signal,
            tick: tick,
            allLightsOn: allLightsOn,
            customization: customization
        ) > 0
    }

    private static func activeIntensity(
        _ color: SignalLampColor,
        signal: RuntimeSignal,
        tick: Int,
        customization: SignalEffectCustomization
    ) -> Double {
        let activeTick = adjustedTick(tick, speed: customization.activeSpeed)
        let activeEffect = signal == .thinking ? customization.thinkingEffect : customization.activeEffect

        switch activeEffect {
        case .greenBreathing:
            guard color == .green else { return 0 }
            let values: [Double] = [0.35, 0.42, 0.52, 0.66, 0.82, 1.0, 0.82, 0.66, 0.52, 0.42]
            return values[activeTick % values.count]
        case .greenSteady:
            return color == .green ? 1 : 0
        case .greenSlowFlash:
            guard color == .green else { return 0 }
            let values: [Double] = [1, 1, 1, 0, 0, 0]
            return values[activeTick % values.count]
        case .greenFastFlash:
            guard color == .green else { return 0 }
            let values: [Double] = [1, 0]
            return values[activeTick % values.count]
        case .trafficCycle:
            let phaseColors: [SignalLampColor] = [.red, .yellow, .green]
            let ticksPerColor = 4
            let phase = (activeTick / ticksPerColor) % phaseColors.count
            guard color == phaseColors[phase] else { return 0 }
            return 1
        }
    }

    private static func completedIntensity(
        _ color: SignalLampColor,
        tick: Int,
        customization: SignalEffectCustomization
    ) -> Double {
        let completedTick = adjustedTick(tick, speed: customization.alertSpeed)
        let pulseValues: [Double] = [1.0, 0.7, 0, 0]

        switch customization.completedEffect {
        case .greenPulse:
            guard color == .green else { return 0 }
            return pulseValues[completedTick % pulseValues.count]
        case .greenSteady:
            return color == .green ? 1 : 0
        case .yellowPulse:
            guard color == .yellow else { return 0 }
            return pulseValues[completedTick % pulseValues.count]
        case .yellowSteady:
            return color == .yellow ? 1 : 0
        case .allSteady:
            return 1
        case .allPulse:
            return pulseValues[completedTick % pulseValues.count]
        }
    }

    private static func adjustedTick(_ tick: Int, speed: SignalEffectSpeed) -> Int {
        let tick = normalizedTick(tick)
        switch speed {
        case .slow:
            return tick / 2
        case .standard:
            return tick
        case .fast:
            return tick * 2
        }
    }

    private static func blockedTick(_ tick: Int, speed: SignalEffectSpeed) -> Int {
        let tick = normalizedTick(tick)
        switch speed {
        case .slow:
            return tick / 2
        case .standard, .fast:
            return tick
        }
    }

    private static func normalizedTick(_ tick: Int) -> Int {
        tick >= 0 ? tick : 0
    }
}
