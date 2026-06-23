import CodexAgentRuntimeSignalCore
import CodexAgentRuntimeSignalUI
import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class SignalAnimationClock: ObservableObject {
    @Published private(set) var tick: Int = 0

    func advance(by step: Int = 1) {
        tick = (tick + max(step, 1)) % 10_000
    }

    func reset() {
        if tick != 0 {
            tick = 0
        }
    }
}

enum RuntimeSignalAgentScopeGroup: Int, CaseIterable, Hashable {
    case codex
    case claude
    case other
}

enum RuntimeSignalAgentScope: String, CaseIterable, Hashable {
    case codex
    case claude
    case codexDesktop = "codex-desktop"
    case codexCLI = "codex-cli"
    case codexVSCode = "codex-vscode"
    case codexXcode = "codex-xcode"
    case codexIDEA = "codex-idea"
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"
    case localScript = "local-script"

    static let selectableCases: [RuntimeSignalAgentScope] = [
        .codexDesktop,
        .codexCLI,
        .codexVSCode,
        .codexXcode,
        .codexIDEA,
        .claudeCode,
        .localScript
    ]

    static let allCases: [RuntimeSignalAgentScope] = selectableCases

    static let defaultSelectedCases: Set<RuntimeSignalAgentScope> = [
        .codexDesktop,
        .codexCLI,
        .codexVSCode,
        .codexXcode,
        .codexIDEA
    ]

    static let codexCases: Set<RuntimeSignalAgentScope> = [
        .codexDesktop,
        .codexCLI,
        .codexVSCode,
        .codexXcode,
        .codexIDEA
    ]

    static let claudeCases: Set<RuntimeSignalAgentScope> = [
        .claudeCode
    ]

    var group: RuntimeSignalAgentScopeGroup {
        switch self {
        case .codex, .codexDesktop, .codexCLI, .codexVSCode, .codexXcode, .codexIDEA:
            return .codex
        case .claude, .claudeCode, .claudeDesktop:
            return .claude
        case .localScript:
            return .other
        }
    }

    var sortOrder: Int {
        switch self {
        case .codexDesktop:
            return 0
        case .codexCLI:
            return 1
        case .codexVSCode:
            return 2
        case .codexXcode:
            return 3
        case .codexIDEA:
            return 4
        case .claudeCode:
            return 5
        case .claudeDesktop:
            return 6
        case .localScript:
            return 7
        case .codex:
            return 100
        case .claude:
            return 101
        }
    }

    var expandedSelection: Set<RuntimeSignalAgentScope> {
        switch self {
        case .codex:
            return Self.codexCases
        case .claude:
            return Self.claudeCases
        default:
            return Self.selectableCases.contains(self) ? [self] : []
        }
    }

    func matches(session: SessionStatus) -> Bool {
        matches(
            sourceKey: ActivityPresentation.activitySourceKey(for: session),
            agent: session.agent,
            sessionID: session.sessionID
        )
    }

    func matches(event: RecentSignalEvent) -> Bool {
        matches(
            sourceKey: ActivityPresentation.activitySourceKey(for: event),
            agent: event.agent,
            sessionID: event.sessionID
        )
    }

    private func matches(sourceKey: String, agent: String?, sessionID: String) -> Bool {
        let normalizedAgent = Self.normalizedAgentName(agent)
        let normalizedSessionID = sessionID.lowercased()

        switch self {
        case .codex:
            return sourceKey.hasPrefix("codex:")
        case .claude:
            return sourceKey.hasPrefix("claude:")
        case .codexDesktop:
            return sourceKey == "codex:desktop"
                || normalizedAgent == "codex-desktop"
                || normalizedSessionID.hasPrefix("codex-desktop:")
        case .codexCLI:
            return sourceKey == "codex:terminal"
                || normalizedAgent == "codex-cli"
                || normalizedAgent == "codex-terminal"
                || normalizedSessionID.hasPrefix("codex-cli:")
        case .codexVSCode:
            return sourceKey == "codex:ide:vs-code"
                || normalizedAgent == "codex-vscode"
                || normalizedAgent == "vscode-codex"
                || normalizedSessionID.hasPrefix("codex-vscode:")
        case .codexXcode:
            return sourceKey == "codex:ide:xcode"
                || normalizedAgent == "codex-xcode"
                || normalizedAgent == "xcode-codex"
                || normalizedSessionID.hasPrefix("codex-xcode:")
        case .codexIDEA:
            return sourceKey == "codex:ide:idea"
                || sourceKey == "codex:ide:jetbrains"
                || normalizedAgent == "codex-idea"
                || normalizedAgent == "codex-intellij"
                || normalizedAgent == "codex-jetbrains"
                || normalizedSessionID.hasPrefix("codex-idea:")
        case .claudeCode:
            return sourceKey == "claude:terminal"
                || sourceKey == "claude:desktop"
                || normalizedAgent == "claude-code"
                || normalizedAgent == "claude-cli"
                || normalizedAgent == "claude-desktop"
                || normalizedSessionID.hasPrefix("claude-code:")
                || normalizedSessionID.hasPrefix("claude-cli:")
                || normalizedSessionID.hasPrefix("claude-desktop:")
        case .claudeDesktop:
            return sourceKey == "claude:desktop"
                || normalizedAgent == "claude-desktop"
                || normalizedSessionID.hasPrefix("claude-desktop:")
        case .localScript:
            return !sourceKey.hasPrefix("codex:")
                && !sourceKey.hasPrefix("claude:")
                && !normalizedAgent.isEmpty
        }
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

enum SettingsGlassEffect: String, CaseIterable, Hashable {
    case reduced
    case standard

    static func preferenceValue(for rawValue: String?) -> SettingsGlassEffect? {
        guard let rawValue else { return nil }
        if rawValue == "enhanced" {
            return .standard
        }
        return SettingsGlassEffect(rawValue: rawValue)
    }
}

enum StatusMenuMode: String, CaseIterable, Hashable {
    case detailed
    case simple
}

enum RuntimeSignalAgentSelectionMode: String, Hashable {
    case following
    case manual
}

struct StatusLightOverrideFrame: Equatable {
    let signal: RuntimeSignal
    let tick: Int
    let allLightsOn: Bool
    let usesSystemGrayLights: Bool
    let effectCustomization: SignalEffectCustomization

    init(
        signal: RuntimeSignal,
        tick: Int,
        allLightsOn: Bool,
        usesSystemGrayLights: Bool = false,
        effectCustomization: SignalEffectCustomization
    ) {
        self.signal = signal
        self.tick = tick
        self.allLightsOn = allLightsOn
        self.usesSystemGrayLights = usesSystemGrayLights
        self.effectCustomization = effectCustomization
    }
}

struct RuntimeTimingProfile: Equatable {
    let statePollInterval: TimeInterval
    let statePollTolerance: TimeInterval
    let animationTickInterval: TimeInterval
    let animationTickTolerance: TimeInterval
    let agentPollInterval: TimeInterval
    let agentPollTolerance: TimeInterval
    let desktopAppPresencePollInterval: TimeInterval
    let desktopAppPresencePollTolerance: TimeInterval
    let automaticUpdateCheckTimerInterval: TimeInterval
    let automaticUpdateCheckTimerTolerance: TimeInterval

    static let standard = RuntimeTimingProfile(
        statePollInterval: 12.0,
        statePollTolerance: 4.0,
        animationTickInterval: 0.9,
        animationTickTolerance: 0.3,
        agentPollInterval: 10.0,
        agentPollTolerance: 3.0,
        desktopAppPresencePollInterval: 60.0,
        desktopAppPresencePollTolerance: 15.0,
        automaticUpdateCheckTimerInterval: 60 * 60,
        automaticUpdateCheckTimerTolerance: 5 * 60
    )

    static let lowPower = RuntimeTimingProfile(
        statePollInterval: 30.0,
        statePollTolerance: 8.0,
        animationTickInterval: 1.5,
        animationTickTolerance: 0.5,
        agentPollInterval: 20.0,
        agentPollTolerance: 6.0,
        desktopAppPresencePollInterval: 120.0,
        desktopAppPresencePollTolerance: 30.0,
        automaticUpdateCheckTimerInterval: 60 * 60,
        automaticUpdateCheckTimerTolerance: 5 * 60
    )
}

enum HookInstallOperation: Hashable {
    case preview
    case install
    case uninstall
    case message
}

@MainActor
final class MenuBarStatusModel: ObservableObject {
    @Published private(set) var snapshot: SignalSnapshot
    @Published var displayLayout: TrafficSignalLayout
    @Published var statusBarStyle: TrafficSignalStyle
    @Published var macOSBreathingStrength: MacOSBreathingStrength
    @Published var thinkingSignalEffect: ActiveSignalEffect
    @Published var activeSignalEffect: ActiveSignalEffect
    @Published var activeEffectSpeed: SignalEffectSpeed
    @Published var alertEffectSpeed: SignalEffectSpeed
    @Published var completedSignalEffect: CompletedSignalEffect
    @Published var macOSHorizontalUsesTrafficLightSize: Bool
    @Published var trafficLightVerticalUsesMacOSSize: Bool
    @Published var isStatusBarIconEnabled: Bool
    @Published var runtimeSignalAgentScopes: Set<RuntimeSignalAgentScope>
    @Published private(set) var runtimeSignalAgentSelectionMode: RuntimeSignalAgentSelectionMode
    @Published var statusMenuMode: StatusMenuMode
    @Published var isCodexDesktopMonitoringEnabled: Bool
    @Published var isClaudeDesktopMonitoringEnabled: Bool
    @Published var appLanguage: AppLanguage
    @Published var appTheme: AppTheme
    @Published var isSettingsGlassEnabled: Bool
    @Published var settingsGlassEffect: SettingsGlassEffect
    @Published var isLowPowerModeEnabled: Bool
    @Published var isNewZealandTrafficLightModeEnabled: Bool
    @Published var isMonitoringPaused = false
    @Published var isCompletionBubbleEnabled: Bool
    @Published var completionBubbleCompletionSound: TaskStatusBubbleSound
    @Published var completionBubblePermissionSound: TaskStatusBubbleSound
    @Published private(set) var statusLightOverride: StatusLightOverrideFrame?
    @Published private(set) var desktopAppSessions: [SessionStatus] = []
    @Published private(set) var isLaunchAtLoginEnabled = false
    @Published private(set) var isLaunchAtLoginChangeRunning = false
    @Published var isHookInstallRunning = false
    @Published var hookInstallMessage: String?
    @Published var hookInstallOperation: HookInstallOperation = .message
    @Published var isDiagnosticsExportRunning = false
    @Published var diagnosticsExportMessage: String?
    @Published private(set) var releaseInfo: ReleaseInfo = .current()
    @Published private(set) var isUpdateCheckRunning = false
    @Published private(set) var isAutomaticUpdateCheckEnabled = false
    @Published private(set) var lastAutomaticUpdateCheckAt: Date?
    @Published var updateCheckMessage: String?
    @Published private(set) var updateReleasePageURL: URL?
    @Published var lastError: String?
    @Published private(set) var completionBubbleCompletionSoundTestTick = 0
    @Published private(set) var completionBubblePermissionSoundTestTick = 0

    let animationClock = SignalAnimationClock()

    private let store: SignalStateStore
    private let launchAtLoginManager: LaunchAtLoginManager
    private let hookInstallManager: HookInstallManager
    private let diagnosticsExportManager: DiagnosticsExportManager
    private let codexDesktopActivityMonitor: CodexDesktopActivityMonitor
    private let codexPlatformPresenceMonitor: CodexPlatformPresenceMonitor
    let codexThreadNameResolver: CodexThreadNameResolving
    private let updateChecker: GitHubReleaseUpdateChecker
    private let stateReloadQueue = DispatchQueue(label: "com.codexagentruntimesignal.state-reload")
    private let codexDesktopPollQueue = DispatchQueue(label: "com.codexagentruntimesignal.codex-desktop-poll")
    private let platformPresencePollQueue = DispatchQueue(label: "com.codexagentruntimesignal.platform-presence-poll")
    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private var codexDesktopTimer: Timer?
    private var desktopAppTimer: Timer?
    private var automaticUpdateCheckTimer: Timer?
    private var watcher: StateFileWatcher?
    private static let recentEventDeduplicationWindow: TimeInterval = 4
    private static let completedDisplayWindow: TimeInterval = 30
    private static let recentActivityFallbackWindow: TimeInterval = 5 * 60
    private static let desktopPresenceSuppressionWindow: TimeInterval = 5 * 60
    private static let openCodexSessionRetentionWindow: TimeInterval = 10 * 60
    private static let passiveActiveDisplayWindow: TimeInterval = 45
    private static let combinedDisplaySessionsCacheTTL: TimeInterval = 1
    private var statusLightSequence: [StatusLightOverrideFrame] = []
    private var statusLightSequenceIndex = 0
    private var animationFrameSkipCounter = 0
    private var isStateReloadInFlight = false
    private var isStateReloadQueued = false
    private var isCodexDesktopPollInFlight = false
    private var isPlatformPresencePollInFlight = false
    private var isAutomaticUpdateCheckInFlight = false
    private var retainedOpenCodexSessionsByID: [String: SessionStatus] = [:]
    private var retainedOpenCodexSessionSeenAtByID: [String: Date] = [:]
    private var stableSessionOrderByIdentityKey: [String: Int] = [:]
    private var nextStableSessionOrder = 0
    private var cachedCombinedDisplaySessions: CombinedDisplaySessionsCache?
    private var cachedDisplaySnapshot: DisplaySnapshotCache?
    private var lastNotifiedUpdateVersion: String?

    private static let defaultDisplayLayout: TrafficSignalLayout = .horizontal
    private static let defaultStatusBarStyle: TrafficSignalStyle = .macOS
    private static let defaultMacOSHorizontalUsesTrafficLightSize = true
    private static let defaultTrafficLightVerticalUsesMacOSSize = false
    private static let effectDefaultsVersion = 2
    private static let preferenceDefaultsVersion = 1
    private static let automaticUpdateCheckInterval: TimeInterval = 24 * 60 * 60
    private static let activeDisplayWindow: TimeInterval = SignalStateStore.defaultSessionTTL()

    private struct LaunchAtLoginUpdateResult: Sendable {
        let isEnabled: Bool
        let errorMessage: String?
    }

    private struct AnimationTickCadence {
        let timerFramesPerAdvance: Int
        let tickAdvance: Int

        static let everyFrame = AnimationTickCadence(timerFramesPerAdvance: 1, tickAdvance: 1)
    }

    private struct CombinedDisplaySessionsCache {
        let snapshot: SignalSnapshot
        let desktopAppSessions: [SessionStatus]
        let loadedAt: Date
        let sessions: [SessionStatus]
    }

    private struct DisplaySnapshotCache {
        let snapshot: SignalSnapshot
        let desktopAppSessions: [SessionStatus]
        let runtimeSignalAgentScopes: Set<RuntimeSignalAgentScope>
        let runtimeSignalAgentSelectionMode: RuntimeSignalAgentSelectionMode
        let loadedAt: Date
        let displaySnapshot: SignalSnapshot
    }

    init(
        store: SignalStateStore = SignalStateStore(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        hookInstallManager: HookInstallManager = HookInstallManager(),
        diagnosticsExportManager: DiagnosticsExportManager = DiagnosticsExportManager(),
        codexDesktopActivityMonitor: CodexDesktopActivityMonitor = CodexDesktopActivityMonitor(),
        codexPlatformPresenceMonitor: CodexPlatformPresenceMonitor = CodexPlatformPresenceMonitor(),
        codexThreadNameResolver: CodexThreadNameResolving = CodexThreadNameIndex(),
        updateChecker: GitHubReleaseUpdateChecker = GitHubReleaseUpdateChecker()
    ) {
        self.store = store
        self.launchAtLoginManager = launchAtLoginManager
        self.hookInstallManager = hookInstallManager
        self.diagnosticsExportManager = diagnosticsExportManager
        self.codexDesktopActivityMonitor = codexDesktopActivityMonitor
        self.codexPlatformPresenceMonitor = codexPlatformPresenceMonitor
        self.codexThreadNameResolver = codexThreadNameResolver
        self.updateChecker = updateChecker
        let storedLayout = UserDefaults.standard.string(forKey: "trafficSignalLayout")
        let storedStyle = UserDefaults.standard.string(forKey: "trafficSignalStyle")
        let storedMacOSStrength = UserDefaults.standard.string(forKey: "macOSBreathingStrength")
        let storedThinkingSignalEffect = UserDefaults.standard.string(forKey: "thinkingSignalEffect")
        let storedActiveSignalEffect = UserDefaults.standard.string(forKey: "activeSignalEffect")
        let storedActiveEffectSpeed = UserDefaults.standard.string(forKey: "activeEffectSpeed")
        let storedAlertEffectSpeed = UserDefaults.standard.string(forKey: "alertEffectSpeed")
        let storedCompletedSignalEffect = UserDefaults.standard.string(forKey: "completedSignalEffect")
        let storedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        let storedTheme = UserDefaults.standard.string(forKey: "appTheme")
        let storedSettingsGlassEnabled = UserDefaults.standard.object(forKey: "isSettingsGlassEnabled") as? Bool
        let storedSettingsGlassEffect =
            UserDefaults.standard.string(forKey: "settingsGlassEffect")
            ?? UserDefaults.standard.string(forKey: "settingsMenuGlassEffect")
        let storedLowPowerModeEnabled =
            UserDefaults.standard.object(forKey: "isLowPowerModeEnabled") as? Bool
        let storedNewZealandTrafficLightModeEnabled =
            UserDefaults.standard.object(forKey: "isNewZealandTrafficLightModeEnabled") as? Bool
        let storedRuntimeSignalAgentScope = UserDefaults.standard.string(forKey: "runtimeSignalAgentScope")
        let storedRuntimeSignalAgentScopes = UserDefaults.standard.stringArray(forKey: "runtimeSignalAgentScopes")
        let storedRuntimeSignalAgentSelectionMode = UserDefaults.standard.string(forKey: "runtimeSignalAgentSelectionMode")
        let storedStatusMenuMode = UserDefaults.standard.string(forKey: "statusMenuMode")
        let storedCompletionBubbleEnabled =
            UserDefaults.standard.object(forKey: "isCompletionBubbleEnabled") as? Bool
        let storedCompletionBubbleCompletionSound =
            UserDefaults.standard.string(forKey: "completionBubbleCompletionSound")
        let storedCompletionBubblePermissionSound =
            UserDefaults.standard.string(forKey: "completionBubblePermissionSound")
        let storedAutomaticUpdateCheckEnabled =
            UserDefaults.standard.object(forKey: "isAutomaticUpdateCheckEnabled") as? Bool
        let storedLastAutomaticUpdateCheckAt =
            UserDefaults.standard.object(forKey: "lastAutomaticUpdateCheckAt") as? Date
        let shouldApplyPreferenceDefaults =
            UserDefaults.standard.integer(forKey: "settingsPreferenceDefaultsVersion")
                < Self.preferenceDefaultsVersion
        let shouldApplyEffectDefaults = UserDefaults.standard.integer(forKey: "signalEffectDefaultsVersion") < Self.effectDefaultsVersion
        let resolvedDisplayLayout =
            storedLayout.flatMap(TrafficSignalLayout.init(rawValue:)) ?? Self.defaultDisplayLayout
        displayLayout = resolvedDisplayLayout
        statusBarStyle = storedStyle.flatMap(TrafficSignalStyle.init(rawValue:)) ?? Self.defaultStatusBarStyle
        let storedMacOSBreathingStrength = storedMacOSStrength.flatMap(MacOSBreathingStrength.init(rawValue:))
        let resolvedMacOSBreathingStrength = storedMacOSBreathingStrength ?? .pronounced
        macOSBreathingStrength = resolvedMacOSBreathingStrength
        if storedMacOSBreathingStrength == nil {
            UserDefaults.standard.set(resolvedMacOSBreathingStrength.rawValue, forKey: "macOSBreathingStrength")
        }
        let resolvedThinkingSignalEffect: ActiveSignalEffect = shouldApplyEffectDefaults
            ? .greenFastFlash
            : storedThinkingSignalEffect.flatMap(ActiveSignalEffect.init(rawValue:)) ?? .greenFastFlash
        let resolvedActiveSignalEffect: ActiveSignalEffect = shouldApplyEffectDefaults
            ? .greenSlowFlash
            : storedActiveSignalEffect.flatMap(ActiveSignalEffect.init(rawValue:)) ?? .greenSlowFlash
        thinkingSignalEffect = resolvedThinkingSignalEffect
        activeSignalEffect = resolvedActiveSignalEffect
        activeEffectSpeed = storedActiveEffectSpeed.flatMap(SignalEffectSpeed.init(rawValue:)) ?? .standard
        alertEffectSpeed = storedAlertEffectSpeed.flatMap(SignalEffectSpeed.init(rawValue:)) ?? .standard
        let resolvedCompletedSignalEffect: CompletedSignalEffect = shouldApplyEffectDefaults
            ? .greenSteady
            : storedCompletedSignalEffect.flatMap(CompletedSignalEffect.init(rawValue:)) ?? .greenSteady
        completedSignalEffect = resolvedCompletedSignalEffect
        if shouldApplyEffectDefaults {
            UserDefaults.standard.set(resolvedThinkingSignalEffect.rawValue, forKey: "thinkingSignalEffect")
            UserDefaults.standard.set(resolvedActiveSignalEffect.rawValue, forKey: "activeSignalEffect")
            UserDefaults.standard.set(resolvedCompletedSignalEffect.rawValue, forKey: "completedSignalEffect")
            UserDefaults.standard.set(Self.effectDefaultsVersion, forKey: "signalEffectDefaultsVersion")
        }
        appLanguage = storedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .system
        appTheme = storedTheme.flatMap(AppTheme.init(rawValue:)) ?? .system
        isSettingsGlassEnabled = storedSettingsGlassEnabled ?? true
        settingsGlassEffect =
            SettingsGlassEffect.preferenceValue(for: storedSettingsGlassEffect) ?? .reduced
        isLowPowerModeEnabled = storedLowPowerModeEnabled ?? true
        let resolvedNewZealandTrafficLightModeEnabled = storedNewZealandTrafficLightModeEnabled ?? true
        isNewZealandTrafficLightModeEnabled = resolvedNewZealandTrafficLightModeEnabled
        if storedNewZealandTrafficLightModeEnabled == nil {
            UserDefaults.standard.set(
                resolvedNewZealandTrafficLightModeEnabled,
                forKey: "isNewZealandTrafficLightModeEnabled"
            )
        }
        isCompletionBubbleEnabled = storedCompletionBubbleEnabled ?? true
        completionBubbleCompletionSound =
            storedCompletionBubbleCompletionSound.flatMap(TaskStatusBubbleSound.init(rawValue:)) ?? .glass
        completionBubblePermissionSound =
            storedCompletionBubblePermissionSound.flatMap(TaskStatusBubbleSound.init(rawValue:)) ?? .ping
        macOSHorizontalUsesTrafficLightSize =
            UserDefaults.standard.object(forKey: "macOSHorizontalUsesTrafficLightSize") as? Bool
            ?? UserDefaults.standard.object(forKey: "macOSUsesTrafficLightSize") as? Bool
            ?? Self.defaultMacOSHorizontalUsesTrafficLightSize
        trafficLightVerticalUsesMacOSSize =
            UserDefaults.standard.object(forKey: "trafficLightVerticalUsesMacOSSize") as? Bool
            ?? Self.defaultTrafficLightVerticalUsesMacOSSize
        let storedStatusBarIconEnabled = UserDefaults.standard.object(forKey: "isStatusBarIconEnabled") as? Bool ?? true
        isStatusBarIconEnabled = DebugLaunchOptions.shouldForceStatusBarIconEnabled ? true : storedStatusBarIconEnabled
        UserDefaults.standard.set(false, forKey: "isStatusBarAllLightsOn")
        runtimeSignalAgentScopes = Self.resolvedRuntimeSignalAgentScopes(
            storedScopes: storedRuntimeSignalAgentScopes,
            legacyScope: storedRuntimeSignalAgentScope
        )
        runtimeSignalAgentSelectionMode = Self.resolvedRuntimeSignalAgentSelectionMode(
            storedMode: storedRuntimeSignalAgentSelectionMode,
            storedScopes: storedRuntimeSignalAgentScopes,
            legacyScope: storedRuntimeSignalAgentScope
        )
        let storedStatusMenuModeValue = storedStatusMenuMode.flatMap(StatusMenuMode.init(rawValue:))
        let resolvedStatusMenuMode = storedStatusMenuModeValue ?? .simple
        statusMenuMode = resolvedStatusMenuMode
        if storedStatusMenuModeValue == nil {
            UserDefaults.standard.set(resolvedStatusMenuMode.rawValue, forKey: "statusMenuMode")
        }
        isCodexDesktopMonitoringEnabled =
            UserDefaults.standard.object(forKey: "isCodexDesktopMonitoringEnabled") as? Bool ?? true
        isClaudeDesktopMonitoringEnabled =
            UserDefaults.standard.object(forKey: "isClaudeDesktopMonitoringEnabled") as? Bool ?? true
        let resolvedAutomaticUpdateCheckEnabled = false
        isAutomaticUpdateCheckEnabled = resolvedAutomaticUpdateCheckEnabled
        if storedAutomaticUpdateCheckEnabled != resolvedAutomaticUpdateCheckEnabled {
            UserDefaults.standard.set(resolvedAutomaticUpdateCheckEnabled, forKey: "isAutomaticUpdateCheckEnabled")
        }
        lastAutomaticUpdateCheckAt = storedLastAutomaticUpdateCheckAt
        lastNotifiedUpdateVersion = UserDefaults.standard.string(forKey: "lastNotifiedUpdateVersion")
        snapshot = store.readSnapshot()
        isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        if shouldApplyPreferenceDefaults {
            enableLaunchAtLoginByDefaultIfNeeded()
            UserDefaults.standard.set(Self.preferenceDefaultsVersion, forKey: "settingsPreferenceDefaultsVersion")
        }
        desktopAppSessions = stabilizedPlatformPresenceSessions(
            filteredPlatformPresenceSessions(codexPlatformPresenceMonitor.detectSessions()),
            now: Date()
        )
        watcher = StateFileWatcher(stateFileURL: snapshot.stateFileURL) { [weak self] in
            self?.reloadFromWatcher()
        }
        watcher?.start()
        startTimers()
        startMonitoringResumeLightSequence()
    }

    func reload() {
        let latestReleaseInfo = ReleaseInfo.current()
        if latestReleaseInfo != releaseInfo {
            releaseInfo = latestReleaseInfo
        }

        enqueueStateReload()
    }

    func reloadSynchronouslyForUserInteraction() {
        let latestReleaseInfo = ReleaseInfo.current()
        if latestReleaseInfo != releaseInfo {
            releaseInfo = latestReleaseInfo
        }

        reloadSnapshotSynchronouslyForTesting()
        refreshDesktopAppPresenceForUserInteraction()
    }

    func reloadSnapshotSynchronouslyForTesting() {
        let latestSnapshot = store.readSnapshot()
        if latestSnapshot != snapshot {
            snapshot = latestSnapshot
            invalidateDisplayCaches()
        }
    }

    func reloadFromWatcher() {
        guard !isMonitoringPaused else { return }
        reload()
    }

    func setManualSignal(_ signal: RuntimeSignal) {
        do {
            snapshot = try store.setManualSignal(signal)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearSessions() {
        do {
            snapshot = try store.clearSessions()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setMonitoringPaused(_ paused: Bool) {
        guard paused != isMonitoringPaused else { return }
        isMonitoringPaused = paused

        if paused {
            startMonitoringPauseLightSequence()
            pollDesktopAppPresence()
        } else {
            reload()
            pollDesktopAppPresence()
            startMonitoringResumeLightSequence()
        }
    }

    func toggleMonitoring() {
        setMonitoringPaused(!isMonitoringPaused)
    }

    func setDisplayLayout(_ layout: TrafficSignalLayout) {
        displayLayout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: "trafficSignalLayout")
    }

    func setStatusBarStyle(_ style: TrafficSignalStyle) {
        statusBarStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "trafficSignalStyle")
    }

    func setMacOSBreathingStrength(_ strength: MacOSBreathingStrength) {
        macOSBreathingStrength = strength
        UserDefaults.standard.set(strength.rawValue, forKey: "macOSBreathingStrength")
    }

    func setThinkingSignalEffect(_ effect: ActiveSignalEffect) {
        thinkingSignalEffect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "thinkingSignalEffect")
    }

    func setActiveSignalEffect(_ effect: ActiveSignalEffect) {
        activeSignalEffect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "activeSignalEffect")
    }

    func setActiveEffectSpeed(_ speed: SignalEffectSpeed) {
        activeEffectSpeed = speed
        UserDefaults.standard.set(speed.rawValue, forKey: "activeEffectSpeed")
    }

    func setAlertEffectSpeed(_ speed: SignalEffectSpeed) {
        alertEffectSpeed = speed
        UserDefaults.standard.set(speed.rawValue, forKey: "alertEffectSpeed")
    }

    func setCompletedSignalEffect(_ effect: CompletedSignalEffect) {
        completedSignalEffect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "completedSignalEffect")
    }

    var signalEffectCustomization: SignalEffectCustomization {
        SignalEffectCustomization(
            thinkingEffect: thinkingSignalEffect,
            activeEffect: activeSignalEffect,
            activeSpeed: activeEffectSpeed,
            alertSpeed: alertEffectSpeed,
            completedEffect: completedSignalEffect
        )
    }

    var tick: Int {
        animationClock.tick
    }

    var lightSnapshot: SignalSnapshot {
        let baseSnapshot = displaySnapshot
        if let statusLightOverride {
            return snapshot(baseSnapshot, overridingAggregate: statusLightOverride.signal)
        }

        if isMonitoringPaused {
            return snapshot(baseSnapshot, overridingAggregate: .off)
        }

        return baseSnapshot
    }

    var lightTick: Int {
        return statusLightOverride?.tick ?? animationClock.tick
    }

    var lightAllLightsOn: Bool {
        if statusLightOverride == nil, isMonitoringPaused {
            return true
        }

        return statusLightOverride?.allLightsOn ?? false
    }

    var lightUsesSystemGrayLights: Bool {
        return statusLightOverride?.usesSystemGrayLights ?? isMonitoringPaused
    }

    var lightEffectCustomization: SignalEffectCustomization {
        return statusLightOverride?.effectCustomization ?? signalEffectCustomization
    }

    var runtimeTimingProfile: RuntimeTimingProfile {
        isLowPowerModeEnabled ? .lowPower : .standard
    }

    func setMacOSHorizontalUsesTrafficLightSize(_ enabled: Bool) {
        macOSHorizontalUsesTrafficLightSize = enabled
        UserDefaults.standard.set(enabled, forKey: "macOSHorizontalUsesTrafficLightSize")
    }

    func setTrafficLightVerticalUsesMacOSSize(_ enabled: Bool) {
        trafficLightVerticalUsesMacOSSize = enabled
        UserDefaults.standard.set(enabled, forKey: "trafficLightVerticalUsesMacOSSize")
    }

    func setStatusBarIconEnabled(_ enabled: Bool) {
        isStatusBarIconEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isStatusBarIconEnabled")
    }

    func setCompletionBubbleEnabled(_ enabled: Bool) {
        isCompletionBubbleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isCompletionBubbleEnabled")
    }

    func setCompletionBubbleCompletionSound(_ sound: TaskStatusBubbleSound) {
        completionBubbleCompletionSound = sound
        UserDefaults.standard.set(sound.rawValue, forKey: "completionBubbleCompletionSound")
    }

    func setCompletionBubblePermissionSound(_ sound: TaskStatusBubbleSound) {
        completionBubblePermissionSound = sound
        UserDefaults.standard.set(sound.rawValue, forKey: "completionBubblePermissionSound")
    }

    func previewCompletionBubbleCompletionSound() {
        completionBubbleCompletionSoundTestTick &+= 1
    }

    func previewCompletionBubblePermissionSound() {
        completionBubblePermissionSoundTestTick &+= 1
    }

    func setRuntimeSignalAgentScopes(_ scopes: Set<RuntimeSignalAgentScope>) {
        let selectableScopes = Set(RuntimeSignalAgentScope.selectableCases)
        let resolvedScopes = scopes.intersection(selectableScopes)
        guard !resolvedScopes.isEmpty else { return }

        runtimeSignalAgentScopes = resolvedScopes
        runtimeSignalAgentSelectionMode = .manual
        UserDefaults.standard.set(
            resolvedScopes
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.rawValue),
            forKey: "runtimeSignalAgentScopes"
        )
        UserDefaults.standard.set(
            runtimeSignalAgentSelectionMode.rawValue,
            forKey: "runtimeSignalAgentSelectionMode"
        )
    }

    func toggleRuntimeSignalAgentScope(_ scope: RuntimeSignalAgentScope) {
        if runtimeSignalAgentSelectionMode == .following {
            setRuntimeSignalAgentScopes([scope])
            return
        }

        var updatedScopes = runtimeSignalAgentScopes
        if updatedScopes.contains(scope) {
            updatedScopes.remove(scope)
        } else {
            updatedScopes.insert(scope)
        }

        setRuntimeSignalAgentScopes(updatedScopes)
    }

    func setStatusMenuMode(_ mode: StatusMenuMode) {
        statusMenuMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "statusMenuMode")
    }

    func setCodexDesktopMonitoringEnabled(_ enabled: Bool) {
        isCodexDesktopMonitoringEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isCodexDesktopMonitoringEnabled")
        if enabled {
            codexDesktopActivityMonitor.reset()
            pollCodexDesktopActivity()
        }
        pollDesktopAppPresence()
    }

    func setClaudeDesktopMonitoringEnabled(_ enabled: Bool) {
        isClaudeDesktopMonitoringEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isClaudeDesktopMonitoringEnabled")
        pollDesktopAppPresence()
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
    }

    func setAppTheme(_ theme: AppTheme) {
        appTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
    }

    func setSettingsGlassEnabled(_ enabled: Bool) {
        isSettingsGlassEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isSettingsGlassEnabled")
    }

    func setSettingsGlassEffect(_ effect: SettingsGlassEffect) {
        settingsGlassEffect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "settingsGlassEffect")
    }

    func setLowPowerModeEnabled(_ enabled: Bool) {
        guard enabled != isLowPowerModeEnabled else { return }
        isLowPowerModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isLowPowerModeEnabled")
        animationFrameSkipCounter = 0
        animationClock.reset()
        restartTimers()
        reload()
        pollCodexDesktopActivity()
        pollDesktopAppPresence()
    }

    func setNewZealandTrafficLightModeEnabled(_ enabled: Bool) {
        guard enabled != isNewZealandTrafficLightModeEnabled else { return }
        isNewZealandTrafficLightModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isNewZealandTrafficLightModeEnabled")
        animationFrameSkipCounter = 0
        animationClock.reset()
    }

    func setAutomaticUpdateCheckEnabled(_ enabled: Bool) {
        guard enabled != isAutomaticUpdateCheckEnabled else { return }
        isAutomaticUpdateCheckEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isAutomaticUpdateCheckEnabled")

        if enabled {
            requestUpdateNotificationAuthorizationIfNeeded()
            performAutomaticUpdateCheckIfNeeded(force: true)
        } else {
            updateCheckMessage = text(
                "已关闭自动检查更新。",
                "Automatic update checks are off."
            )
        }
    }

    var statusBarTooltip: String {
        statusBarTooltip(for: lightSnapshot)
    }

    func statusBarTooltip(for displaySnapshot: SignalSnapshot) -> String {
        var lines = [
            "codex-agent-runtime-signal",
            "\(displayName(for: displaySnapshot.aggregate)) - \(humanAction(for: displaySnapshot.aggregate))"
        ]

        let displayScopes = runtimeSignalAgentScopesForDisplay(from: displaySnapshot.sessions)
        lines.append("\(text("灯效 Agent", "Light Agent")): \(displayName(for: displayScopes))")

        if statusBarStyle == .macOS && displayLayout == .horizontal && !macOSHorizontalUsesTrafficLightSize {
            lines.append(text("圆点横向尺寸：小", "Horizontal dot size: Small"))
        }

        if statusBarStyle == .trafficLight && displayLayout == .vertical && trafficLightVerticalUsesMacOSSize {
            lines.append(text("灯牌竖向尺寸：大", "Vertical lamp size: Large"))
        }

        if isCodexDesktopMonitoringEnabled {
            lines.append(text("Codex 自动监控已开启", "Codex auto monitoring is on"))
        }

        if let session = displaySnapshot.sessions.first {
            var detail = session.sessionID
            if let agent = session.agent, !agent.isEmpty {
                detail += " / \(agent)"
            }
            if let event = session.lastEvent, !event.isEmpty {
                detail += " / \(event)"
            }
            lines.append(detail)
        }

        return lines.joined(separator: "\n")
    }

    var displaySnapshot: SignalSnapshot {
        displaySnapshot()
    }

    private func displaySnapshot(now: Date = Date()) -> SignalSnapshot {
        if let cachedDisplaySnapshot,
           cachedDisplaySnapshot.snapshot == snapshot,
           cachedDisplaySnapshot.desktopAppSessions == desktopAppSessions,
           cachedDisplaySnapshot.runtimeSignalAgentScopes == runtimeSignalAgentScopes,
           cachedDisplaySnapshot.runtimeSignalAgentSelectionMode == runtimeSignalAgentSelectionMode,
           now.timeIntervalSince(cachedDisplaySnapshot.loadedAt) < Self.combinedDisplaySessionsCacheTTL {
            return cachedDisplaySnapshot.displaySnapshot
        }

        let displaySessions = combinedDisplaySessions()
        let displayScopes = runtimeSignalAgentScopesForDisplay(from: displaySessions)
        let scopedDisplaySessions = displaySessions.filter { Self.session($0, matches: displayScopes) }
        let deduplicatedSessions = deduplicatedDisplaySessions(scopedDisplaySessions)
        let scopedRecentEvents = snapshot.recentEvents
            .filter { !Self.isSignalTestEvent($0.event) }
            .filter { Self.event($0, matches: displayScopes) }
        let deduplicatedRecentEvents = deduplicatedRecentEvents(scopedRecentEvents)
        let displayUpdatedAt = deduplicatedSessions.map(\.updatedAt).max()

        let result = SignalSnapshot(
            aggregate: aggregateForRuntimeSignalScopes(
                sessions: deduplicatedSessions,
                fallback: snapshot.aggregate,
                scopes: displayScopes
            ),
            sessions: deduplicatedSessions,
            recentEvents: deduplicatedRecentEvents,
            stateFileURL: snapshot.stateFileURL,
            updatedAt: displayUpdatedAt
        )
        cachedDisplaySnapshot = DisplaySnapshotCache(
            snapshot: snapshot,
            desktopAppSessions: desktopAppSessions,
            runtimeSignalAgentScopes: runtimeSignalAgentScopes,
            runtimeSignalAgentSelectionMode: runtimeSignalAgentSelectionMode,
            loadedAt: now,
            displaySnapshot: result
        )
        return result
    }

    var activitySnapshot: SignalSnapshot {
        let displaySessions = combinedDisplaySessions()
        let activitySessions = deduplicatedActivitySessions(displaySessions)
        let visibleRecentEvents = snapshot.recentEvents
            .filter { !Self.isSignalTestEvent($0.event) }
        let deduplicatedRecentEvents = deduplicatedRecentEvents(visibleRecentEvents)
        let displayUpdatedAt = activitySessions.map(\.updatedAt).max()

        return SignalSnapshot(
            aggregate: aggregateForSessions(activitySessions, fallback: snapshot.aggregate),
            sessions: activitySessions,
            recentEvents: deduplicatedRecentEvents,
            stateFileURL: snapshot.stateFileURL,
            updatedAt: displayUpdatedAt ?? snapshot.updatedAt
        )
    }

    private func enableLaunchAtLoginByDefaultIfNeeded() {
        guard !isLaunchAtLoginEnabled else { return }
        setLaunchAtLoginEnabled(true)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard enabled != isLaunchAtLoginEnabled else { return }
        guard !isLaunchAtLoginChangeRunning else { return }

        isLaunchAtLoginChangeRunning = true
        isLaunchAtLoginEnabled = enabled
        let manager = launchAtLoginManager

        Task { [weak self] in
            let result = await Self.updateLaunchAtLogin(manager: manager, enabled: enabled)

            guard let self else { return }
            isLaunchAtLoginEnabled = result.isEnabled
            lastError = result.errorMessage
            isLaunchAtLoginChangeRunning = false
        }
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLoginEnabled(!isLaunchAtLoginEnabled)
    }

    nonisolated private static func updateLaunchAtLogin(
        manager: LaunchAtLoginManager,
        enabled: Bool
    ) async -> LaunchAtLoginUpdateResult {
        await Task.detached(priority: .userInitiated) {
            do {
                try manager.setEnabled(enabled)
                return LaunchAtLoginUpdateResult(isEnabled: manager.isEnabled, errorMessage: nil)
            } catch {
                return LaunchAtLoginUpdateResult(
                    isEnabled: manager.isEnabled,
                    errorMessage: error.localizedDescription
                )
            }
        }.value
    }

    func previewHookInstall() {
        runHookInstall(operation: .preview) { manager in
            try manager.preview()
        }
    }

    func installHooks() {
        runHookInstall(operation: .install) { manager in
            try manager.install()
        }
    }

    func previewCodexHookInstall() {
        runHookInstall(operation: .preview) { manager in
            try manager.previewCodex()
        }
    }

    func installCodexHooks() {
        runHookInstall(operation: .install) { manager in
            try manager.installCodex()
        }
    }

    func uninstallCodexHooks() {
        runHookInstall(operation: .uninstall) { manager in
            try manager.uninstallCodex()
        }
    }

    func previewClaudeHookInstall() {
        runHookInstall(operation: .preview) { manager in
            try manager.previewClaude()
        }
    }

    func installClaudeHooks() {
        runHookInstall(operation: .install) { manager in
            try manager.installClaude()
        }
    }

    func uninstallClaudeHooks() {
        runHookInstall(operation: .uninstall) { manager in
            try manager.uninstallClaude()
        }
    }

    func openCodex() {
        openAgentApplication(appName: "Codex", displayName: "Codex")
    }

    func openClaude() {
        openAgentApplication(appName: "Claude", displayName: "Claude")
    }

    func showStateFile() {
        NSWorkspace.shared.activateFileViewerSelecting([snapshot.stateFileURL])
    }

    func copyStateFilePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.stateFileURL.path, forType: .string)
    }

    func showReleaseInfoFile() {
        guard let releaseFileURL = releaseInfo.releaseFileURL else {
            lastError = text("没有找到 release 信息文件。", "Release info file was not found.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([releaseFileURL])
    }

    func copyReleaseInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(releaseInfo.clipboardText, forType: .string)
    }

    private func performAutomaticUpdateCheckIfNeeded(force: Bool = false) {
        guard isAutomaticUpdateCheckEnabled else { return }
        guard !isUpdateCheckRunning, !isAutomaticUpdateCheckInFlight else { return }

        let now = Date()
        if !force,
           let lastAutomaticUpdateCheckAt,
           now.timeIntervalSince(lastAutomaticUpdateCheckAt) < Self.automaticUpdateCheckInterval
        {
            return
        }

        let currentVersion = releaseInfo.version
        let checker = updateChecker
        isAutomaticUpdateCheckInFlight = true

        Task {
            let checkedAt = Date()

            do {
                let result = try await checker.check(currentVersion: currentVersion)
                await MainActor.run {
                    self.isAutomaticUpdateCheckInFlight = false
                    self.lastAutomaticUpdateCheckAt = checkedAt
                    UserDefaults.standard.set(checkedAt, forKey: "lastAutomaticUpdateCheckAt")

                    if result.isUpdateAvailable {
                        self.updateReleasePageURL = result.releasePageURL
                        self.updateCheckMessage = self.text(
                            "发现新版本 \(result.latestVersion)（当前 \(result.currentVersion)）。",
                            "Version \(result.latestVersion) is available. Current version: \(result.currentVersion)."
                        )
                        self.notifyUpdateAvailable(result)
                    } else if force {
                        self.updateReleasePageURL = nil
                        self.updateCheckMessage = self.text(
                            "自动检查完成：当前版本 \(result.currentVersion)，已是最新版本。",
                            "Automatic check complete: current version \(result.currentVersion), you are up to date."
                        )
                    }
                }
            } catch {
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    self.isAutomaticUpdateCheckInFlight = false
                    self.lastAutomaticUpdateCheckAt = checkedAt
                    UserDefaults.standard.set(checkedAt, forKey: "lastAutomaticUpdateCheckAt")

                    if force {
                        self.updateReleasePageURL = GitHubReleaseUpdateChecker.fallbackReleasePageURL
                        self.updateCheckMessage = self.text(
                            "自动检查更新失败：\(errorMessage)",
                            "Automatic update check failed: \(errorMessage)"
                        )
                    }
                }
            }
        }
    }

    private func requestUpdateNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func notifyUpdateAvailable(_ result: GitHubUpdateCheckResult) {
        guard result.isUpdateAvailable else { return }
        guard lastNotifiedUpdateVersion != result.latestVersion else { return }

        lastNotifiedUpdateVersion = result.latestVersion
        UserDefaults.standard.set(result.latestVersion, forKey: "lastNotifiedUpdateVersion")

        let content = UNMutableNotificationContent()
        content.title = "codex-agent-runtime-signal"
        content.subtitle = text(
            "发现新版本 \(result.latestVersion)",
            "Version \(result.latestVersion) is available"
        )
        content.body = text(
            "打开关于页面或下载页面更新。",
            "Open the About page or download page to update."
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codex-agent-runtime-signal-bar-update-\(result.latestVersion)",
            content: content,
            trigger: nil
        )

        deliverUpdateNotification(request)
    }

    private func deliverUpdateNotification(_ request: UNNotificationRequest) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    center.add(request)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func checkForUpdates() {
        guard !isUpdateCheckRunning else { return }

        let currentVersion = releaseInfo.version
        let checker = updateChecker
        isUpdateCheckRunning = true
        updateReleasePageURL = nil
        updateCheckMessage = text("正在检查 GitHub Releases...", "Checking GitHub Releases...")
        lastError = nil

        Task {
            do {
                let result = try await checker.check(currentVersion: currentVersion)
                await MainActor.run {
                    self.isUpdateCheckRunning = false
                    self.updateReleasePageURL = result.isUpdateAvailable ? result.releasePageURL : nil
                    if result.isUpdateAvailable {
                        self.updateCheckMessage = self.text(
                            "发现新版本 \(result.latestVersion)（当前 \(result.currentVersion)）。",
                            "Version \(result.latestVersion) is available. Current version: \(result.currentVersion)."
                        )
                    } else {
                        self.updateCheckMessage = self.text(
                            "当前版本 \(result.currentVersion)。已是最新版本。",
                            "Current version \(result.currentVersion). You are up to date."
                        )
                    }
                    self.lastError = nil
                }
            } catch {
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    self.isUpdateCheckRunning = false
                    self.updateReleasePageURL = GitHubReleaseUpdateChecker.fallbackReleasePageURL
                    self.updateCheckMessage = self.text(
                        "检查更新失败：\(errorMessage)",
                        "Update check failed: \(errorMessage)"
                    )
                    self.lastError = nil
                }
            }
        }
    }

    func checkForUpdatesFromAppMenu() {
        guard !isUpdateCheckRunning else { return }

        let currentVersion = releaseInfo.version
        let checker = updateChecker
        isUpdateCheckRunning = true
        updateReleasePageURL = nil
        updateCheckMessage = text("正在检查 GitHub Releases...", "Checking GitHub Releases...")
        lastError = nil

        Task {
            do {
                let result = try await checker.check(currentVersion: currentVersion)
                await MainActor.run {
                    self.isUpdateCheckRunning = false
                    self.updateReleasePageURL = result.isUpdateAvailable ? result.releasePageURL : nil
                    if result.isUpdateAvailable {
                        self.updateCheckMessage = self.text(
                            "发现新版本 \(result.latestVersion)（当前 \(result.currentVersion)）。",
                            "Version \(result.latestVersion) is available. Current version: \(result.currentVersion)."
                        )
                    } else {
                        self.updateCheckMessage = self.text(
                            "当前版本 \(result.currentVersion)。已是最新版本。",
                            "Current version \(result.currentVersion). You are up to date."
                        )
                    }
                    self.lastError = nil
                    self.showUpdateCheckDialog(for: result)
                }
            } catch {
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    self.isUpdateCheckRunning = false
                    self.updateReleasePageURL = GitHubReleaseUpdateChecker.fallbackReleasePageURL
                    self.updateCheckMessage = self.text(
                        "检查更新失败：\(errorMessage)",
                        "Update check failed: \(errorMessage)"
                    )
                    self.lastError = nil
                    self.showUpdateCheckFailureDialog(message: errorMessage)
                }
            }
        }
    }

    private func showUpdateCheckDialog(for result: GitHubUpdateCheckResult) {
        let alert = NSAlert()
        alert.alertStyle = result.isUpdateAvailable ? .informational : .informational
        alert.messageText = result.isUpdateAvailable
            ? text("发现新版本", "Update Available")
            : text("codex-agent-runtime-signal 已是最新版本", "codex-agent-runtime-signal Is Up to Date")
        alert.informativeText = result.isUpdateAvailable
            ? text(
                "版本 \(result.latestVersion) 可用。当前版本：\(result.currentVersion)。",
                "Version \(result.latestVersion) is available. Current version: \(result.currentVersion)."
            )
            : text(
                "当前版本 \(result.currentVersion) 已经是最新版本。",
                "Current version \(result.currentVersion) is already the latest version."
            )

        if result.isUpdateAvailable {
            alert.addButton(withTitle: text("打开下载页面", "Open Download Page"))
            alert.addButton(withTitle: text("稍后", "Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(result.releasePageURL)
            }
        } else {
            alert.addButton(withTitle: text("好", "OK"))
            alert.runModal()
        }
    }

    private func showUpdateCheckFailureDialog(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text("检查更新失败", "Update Check Failed")
        alert.informativeText = message
        alert.addButton(withTitle: text("打开下载页面", "Open Download Page"))
        alert.addButton(withTitle: text("好", "OK"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(GitHubReleaseUpdateChecker.fallbackReleasePageURL)
        }
    }

    func openLatestReleasePage() {
        let url = updateReleasePageURL ?? GitHubReleaseUpdateChecker.fallbackReleasePageURL
        NSWorkspace.shared.open(url)
        lastError = nil
    }

    func copyGenericAgentHookCommand() {
        guard let hookURL = genericAgentHookURL() else {
            lastError = text("没有找到通用 Agent hook 脚本。", "Generic agent hook script was not found.")
            return
        }

        let escapedPath = hookURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let command = """
        printf '{"event":"AgentStarted","agent":"local-script","session_id":"local-script-main"}' | "\(escapedPath)"
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        hookInstallOperation = .message
        hookInstallMessage = text("已复制通用 Agent Hook 命令。", "Generic agent hook command copied.")
        lastError = nil
    }

    func exportDiagnostics() {
        guard !isDiagnosticsExportRunning else { return }
        isDiagnosticsExportRunning = true
        diagnosticsExportMessage = text("正在导出诊断...", "Exporting diagnostics...")
        lastError = nil

        let manager = diagnosticsExportManager
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try manager.export()
            }

            Task { @MainActor in
                self.isDiagnosticsExportRunning = false
                switch result {
                case .success(let output):
                    self.diagnosticsExportMessage = output.displayText
                    self.lastError = nil
                    if let archiveURL = output.archiveURL {
                        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
                    }
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.diagnosticsExportMessage = nil
                }
            }
        }
    }

    private func startTimers() {
        let timingProfile = runtimeTimingProfile

        let pollTimer = Timer(timeInterval: timingProfile.statePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromWatcher()
            }
        }
        pollTimer.tolerance = timingProfile.statePollTolerance
        RunLoop.main.add(pollTimer, forMode: .common)
        self.pollTimer = pollTimer

        let animationTimer = Timer(timeInterval: timingProfile.animationTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.advanceStatusLightSequenceIfNeeded() {
                    self.animationFrameSkipCounter = 0
                    return
                }
                let aggregate = self.lightSnapshot.aggregate
                guard self.shouldAnimateSignal(aggregate) else {
                    self.animationFrameSkipCounter = 0
                    self.animationClock.reset()
                    return
                }
                let cadence = self.animationTickCadence(for: aggregate)
                self.animationFrameSkipCounter += 1
                guard self.animationFrameSkipCounter >= cadence.timerFramesPerAdvance else {
                    return
                }
                self.animationFrameSkipCounter = 0
                self.animationClock.advance(by: cadence.tickAdvance)
            }
        }
        animationTimer.tolerance = timingProfile.animationTickTolerance
        RunLoop.main.add(animationTimer, forMode: .common)
        self.animationTimer = animationTimer

        let codexDesktopTimer = Timer(timeInterval: timingProfile.agentPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollCodexDesktopActivity()
            }
        }
        codexDesktopTimer.tolerance = timingProfile.agentPollTolerance
        RunLoop.main.add(codexDesktopTimer, forMode: .common)
        self.codexDesktopTimer = codexDesktopTimer

        let desktopAppTimer = Timer(
            timeInterval: timingProfile.desktopAppPresencePollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pollDesktopAppPresence()
            }
        }
        desktopAppTimer.tolerance = timingProfile.desktopAppPresencePollTolerance
        RunLoop.main.add(desktopAppTimer, forMode: .common)
        self.desktopAppTimer = desktopAppTimer

        let automaticUpdateCheckTimer = Timer(
            timeInterval: timingProfile.automaticUpdateCheckTimerInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performAutomaticUpdateCheckIfNeeded()
            }
        }
        automaticUpdateCheckTimer.tolerance = timingProfile.automaticUpdateCheckTimerTolerance
        RunLoop.main.add(automaticUpdateCheckTimer, forMode: .common)
        self.automaticUpdateCheckTimer = automaticUpdateCheckTimer
    }

    private func restartTimers() {
        stopTimers()
        startTimers()
    }

    private func stopTimers() {
        pollTimer?.invalidate()
        animationTimer?.invalidate()
        codexDesktopTimer?.invalidate()
        desktopAppTimer?.invalidate()
        automaticUpdateCheckTimer?.invalidate()
        pollTimer = nil
        animationTimer = nil
        codexDesktopTimer = nil
        desktopAppTimer = nil
        automaticUpdateCheckTimer = nil
    }

    private func startMonitoringResumeLightSequence() {
        startStatusLightSequence(Self.monitoringResumeLightSequence)
    }

    private func startMonitoringPauseLightSequence() {
        startStatusLightSequence(Self.monitoringPauseLightSequence)
    }

    private func enqueueStateReload() {
        if isStateReloadInFlight {
            isStateReloadQueued = true
            return
        }

        isStateReloadInFlight = true
        let store = store

        stateReloadQueue.async { [weak self] in
            let latestSnapshot = store.readSnapshot()

            DispatchQueue.main.async { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isStateReloadInFlight = false

                    if latestSnapshot != self.snapshot {
                        self.snapshot = latestSnapshot
                        self.invalidateDisplayCaches()
                    }

                    if self.isStateReloadQueued {
                        self.isStateReloadQueued = false
                        self.enqueueStateReload()
                    }
                }
            }
        }
    }

    private func startStatusLightSequence(_ frames: [StatusLightOverrideFrame]) {
        guard let firstFrame = frames.first else {
            statusLightSequence = []
            statusLightSequenceIndex = 0
            statusLightOverride = nil
            return
        }

        statusLightSequence = frames
        statusLightSequenceIndex = 0
        statusLightOverride = firstFrame
    }

    private func advanceStatusLightSequenceIfNeeded() -> Bool {
        guard !statusLightSequence.isEmpty else { return false }

        let nextIndex = statusLightSequenceIndex + 1
        if nextIndex < statusLightSequence.count {
            statusLightSequenceIndex = nextIndex
            statusLightOverride = statusLightSequence[nextIndex]
        } else {
            statusLightSequence = []
            statusLightSequenceIndex = 0
            statusLightOverride = nil
        }

        return true
    }

    private static var monitoringTransitionCustomization: SignalEffectCustomization {
        SignalEffectCustomization(
            thinkingEffect: .trafficCycle,
            activeEffect: .trafficCycle,
            activeSpeed: .standard,
            alertSpeed: .standard,
            completedEffect: .allSteady
        )
    }

    private static var monitoringResumeLightSequence: [StatusLightOverrideFrame] {
        let customization = monitoringTransitionCustomization
        return [
            StatusLightOverrideFrame(signal: .done, tick: 0, allLightsOn: true, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .done, tick: 0, allLightsOn: true, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .working, tick: 0, allLightsOn: false, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .working, tick: 0, allLightsOn: false, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .working, tick: 4, allLightsOn: false, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .working, tick: 4, allLightsOn: false, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .working, tick: 8, allLightsOn: false, effectCustomization: customization),
            StatusLightOverrideFrame(signal: .working, tick: 8, allLightsOn: false, effectCustomization: customization)
        ]
    }

    private static var monitoringPauseLightSequence: [StatusLightOverrideFrame] {
        let customization = monitoringTransitionCustomization
        return [
            StatusLightOverrideFrame(
                signal: .off,
                tick: 0,
                allLightsOn: true,
                usesSystemGrayLights: true,
                effectCustomization: customization
            )
        ]
    }

    private var shouldAnimateCurrentSignal: Bool {
        shouldAnimateSignal(lightSnapshot.aggregate)
    }

    private func shouldAnimateSignal(_ aggregate: RuntimeSignal) -> Bool {
        switch aggregate.displayState {
        case .ready, .paused:
            return false
        case .active:
            let effect = aggregate == .thinking ? thinkingSignalEffect : activeSignalEffect
            return effect != .greenSteady
        case .completed:
            switch completedSignalEffect {
            case .greenSteady, .yellowSteady, .allSteady:
                return false
            case .greenPulse, .yellowPulse, .allPulse:
                return true
            }
        case .needsReview, .permission, .blocked, .stale:
            return true
        }
    }

    private var animationTickCadenceForCurrentSignal: AnimationTickCadence {
        animationTickCadence(for: lightSnapshot.aggregate)
    }

    private func animationTickCadence(for aggregate: RuntimeSignal) -> AnimationTickCadence {
        if isNewZealandTrafficLightModeEnabled {
            return newZealandAnimationTickCadence(for: aggregate)
        }

        guard isLowPowerModeEnabled else {
            return .everyFrame
        }

        return lowPowerAnimationTickCadence(for: aggregate)
    }

    private var lowPowerAnimationTickCadenceForCurrentSignal: AnimationTickCadence {
        lowPowerAnimationTickCadence(for: lightSnapshot.aggregate)
    }

    private func lowPowerAnimationTickCadence(for aggregate: RuntimeSignal) -> AnimationTickCadence {
        switch aggregate.displayState {
        case .active:
            let effect = aggregate == .thinking ? thinkingSignalEffect : activeSignalEffect
            switch effect {
            case .greenBreathing, .greenSlowFlash, .trafficCycle:
                return AnimationTickCadence(timerFramesPerAdvance: 1, tickAdvance: 2)
            case .greenFastFlash:
                return .everyFrame
            case .greenSteady:
                return .everyFrame
            }
        case .completed:
            switch completedSignalEffect {
            case .greenPulse, .yellowPulse, .allPulse:
                return AnimationTickCadence(timerFramesPerAdvance: 1, tickAdvance: 2)
            case .greenSteady, .yellowSteady, .allSteady:
                return .everyFrame
            }
        case .needsReview, .permission, .stale:
            return AnimationTickCadence(timerFramesPerAdvance: 1, tickAdvance: 2)
        case .blocked:
            return .everyFrame
        case .ready, .paused:
            return .everyFrame
        }
    }

    private var newZealandAnimationTickCadenceForCurrentSignal: AnimationTickCadence {
        newZealandAnimationTickCadence(for: lightSnapshot.aggregate)
    }

    private func newZealandAnimationTickCadence(for aggregate: RuntimeSignal) -> AnimationTickCadence {
        switch aggregate.displayState {
        case .active:
            let effect = aggregate == .thinking ? thinkingSignalEffect : activeSignalEffect
            switch effect {
            case .greenSlowFlash:
                // New Zealand original mode: 0.9s on / 0.9s off, one green flash every 1.8s.
                return AnimationTickCadence(
                    timerFramesPerAdvance: isLowPowerModeEnabled ? 1 : 2,
                    tickAdvance: 3
                )
            case .trafficCycle:
                return AnimationTickCadence(
                    timerFramesPerAdvance: isLowPowerModeEnabled ? 2 : 4,
                    tickAdvance: 4
                )
            case .greenBreathing:
                return isLowPowerModeEnabled
                    ? AnimationTickCadence(timerFramesPerAdvance: 1, tickAdvance: 2)
                    : .everyFrame
            case .greenFastFlash:
                return .everyFrame
            case .greenSteady:
                return .everyFrame
            }
        case .completed:
            switch completedSignalEffect {
            case .greenPulse, .yellowPulse, .allPulse:
                return AnimationTickCadence(
                    timerFramesPerAdvance: isLowPowerModeEnabled ? 1 : 2,
                    tickAdvance: 2
                )
            case .greenSteady, .yellowSteady, .allSteady:
                return .everyFrame
            }
        case .ready, .needsReview, .permission, .blocked, .stale, .paused:
            return isLowPowerModeEnabled
                ? lowPowerAnimationTickCadence(for: aggregate)
                : .everyFrame
        }
    }

    private func pollCodexDesktopActivity() {
        guard isCodexDesktopMonitoringEnabled, !isMonitoringPaused else { return }
        guard !isCodexDesktopPollInFlight else { return }

        isCodexDesktopPollInFlight = true
        let monitor = codexDesktopActivityMonitor
        let store = store

        codexDesktopPollQueue.async { [weak self] in
            let activities = monitor.poll()
            var latestSnapshot: SignalSnapshot?
            var errorMessage: String?

            if !activities.isEmpty {
                do {
                    let now = Date()
                    let updates = activities.map { activity in
                        SignalSessionUpdate(
                            signal: activity.signal,
                            sessionID: activity.sessionID,
                            agent: activity.agent,
                            lastEvent: activity.event,
                            updatedAt: activity.timestamp ?? now
                        )
                    }
                    latestSnapshot = try store.applySessionSignals(updates)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            DispatchQueue.main.async { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isCodexDesktopPollInFlight = false
                    guard self.isCodexDesktopMonitoringEnabled, !self.isMonitoringPaused else { return }
                    if let latestSnapshot {
                        if latestSnapshot != self.snapshot {
                            self.snapshot = latestSnapshot
                        }
                    }
                    if self.lastError != errorMessage {
                        self.lastError = errorMessage
                    }
                }
            }
        }
    }

    private func pollDesktopAppPresence() {
        guard shouldPollPlatformPresence else {
            clearRetainedOpenCodexSessions()
            if !desktopAppSessions.isEmpty {
                desktopAppSessions = []
                invalidateDisplayCaches()
            }
            return
        }

        guard !isPlatformPresencePollInFlight else { return }

        isPlatformPresencePollInFlight = true
        let monitor = codexPlatformPresenceMonitor

        platformPresencePollQueue.async { [weak self] in
            let detectedSessions = monitor.detectSessions()

            DispatchQueue.main.async { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPlatformPresencePollInFlight = false
                    guard self.shouldPollPlatformPresence else {
                        self.clearRetainedOpenCodexSessions()
                        if !self.desktopAppSessions.isEmpty {
                            self.desktopAppSessions = []
                        }
                        return
                    }
                    let latestSessions = self.stabilizedPlatformPresenceSessions(
                        self.filteredPlatformPresenceSessions(detectedSessions),
                        now: Date()
                    )
                    if latestSessions != self.desktopAppSessions {
                        self.desktopAppSessions = latestSessions
                    }
                }
            }
        }
    }

    private var shouldPollPlatformPresence: Bool {
        !isMonitoringPaused
            && (isCodexDesktopMonitoringEnabled || isClaudeDesktopMonitoringEnabled)
    }

    func filteredPlatformPresenceSessions(_ sessions: [SessionStatus]) -> [SessionStatus] {
        sessions.filter { session in
            if session.sessionID.hasPrefix("platform-presence:codex-")
                || session.lastEvent?.hasPrefix("PlatformPresence:") == true
                    && ActivityPresentation.activitySourceKey(for: session).hasPrefix("codex:") {
                return false
            }

            if ActivityPresentation.isTerminalPresenceSession(session) {
                return false
            }

            let sourceKey = ActivityPresentation.activitySourceKey(for: session)
            if sourceKey.hasPrefix("codex:") {
                return isCodexDesktopMonitoringEnabled
            }
            if sourceKey.hasPrefix("claude:") {
                return isClaudeDesktopMonitoringEnabled
            }
            return true
        }
    }

    func stabilizedPlatformPresenceSessions(_ sessions: [SessionStatus], now: Date) -> [SessionStatus] {
        let currentOpenCodexSessions = sessions.filter(ActivityPresentation.isOpenCodexSession)
        let currentOpenCodexSessionIDs = Set(currentOpenCodexSessions.map(\.sessionID))

        for session in currentOpenCodexSessions {
            retainedOpenCodexSessionsByID[session.sessionID] = session
            retainedOpenCodexSessionSeenAtByID[session.sessionID] = now
        }

        retainedOpenCodexSessionsByID = retainedOpenCodexSessionsByID.filter { sessionID, _ in
            guard let seenAt = retainedOpenCodexSessionSeenAtByID[sessionID] else { return false }
            return now.timeIntervalSince(seenAt) <= Self.openCodexSessionRetentionWindow
        }
        retainedOpenCodexSessionSeenAtByID = retainedOpenCodexSessionSeenAtByID.filter { sessionID, seenAt in
            retainedOpenCodexSessionsByID[sessionID] != nil
                && now.timeIntervalSince(seenAt) <= Self.openCodexSessionRetentionWindow
        }

        let retainedSessions = retainedOpenCodexSessionsByID.values.filter { session in
            !currentOpenCodexSessionIDs.contains(session.sessionID)
        }

        return (sessions + retainedSessions).sorted(by: ActivityPresentation.stableSessionSortPrecedes)
    }

    func clearRetainedOpenCodexSessions() {
        retainedOpenCodexSessionsByID = [:]
        retainedOpenCodexSessionSeenAtByID = [:]
    }

    func clearStableSessionOrderForTesting() {
        stableSessionOrderByIdentityKey = [:]
        nextStableSessionOrder = 0
    }

    func refreshDesktopAppPresenceForUserInteraction() {
        guard shouldPollPlatformPresence else {
            clearRetainedOpenCodexSessions()
            if !desktopAppSessions.isEmpty {
                desktopAppSessions = []
            }
            return
        }

        let latestSessions = stabilizedPlatformPresenceSessions(
            filteredPlatformPresenceSessions(
                codexPlatformPresenceMonitor.detectSessions(forceRefresh: true)
            ),
            now: Date()
        )
        if latestSessions != desktopAppSessions {
            desktopAppSessions = latestSessions
            invalidateDisplayCaches()
        }
    }

    func replaceDesktopAppSessionsForTesting(_ sessions: [SessionStatus]) {
        desktopAppSessions = sessions
        invalidateDisplayCaches()
    }

    private func invalidateDisplayCaches() {
        cachedCombinedDisplaySessions = nil
        cachedDisplaySnapshot = nil
    }

    private func combinedDisplaySessions(now: Date = Date()) -> [SessionStatus] {
        if let cachedCombinedDisplaySessions,
           cachedCombinedDisplaySessions.snapshot == snapshot,
           cachedCombinedDisplaySessions.desktopAppSessions == desktopAppSessions,
           now.timeIntervalSince(cachedCombinedDisplaySessions.loadedAt) < Self.combinedDisplaySessionsCacheTTL {
            return cachedCombinedDisplaySessions.sessions
        }

        var sessions = snapshot.sessions.filter { session in
            Self.shouldIncludeStoredSessionInDisplay(session, now: now)
        }
        let liveAgentKeys = Set(
            sessions.compactMap { session -> String? in
                guard Self.shouldSuppressDesktopPresence(for: session, now: now) else { return nil }
                return ActivityPresentation.activitySourceKey(for: session)
            }
        )

        for desktopSession in desktopAppSessions {
            if !ActivityPresentation.isOpenCodexSession(desktopSession) {
                let sourceKey = ActivityPresentation.activitySourceKey(for: desktopSession)
                guard !liveAgentKeys.contains(sourceKey) else { continue }
            }
            sessions.append(desktopSession)
        }

        let sortedSessions = sortSessionsByStableListOrder(sessions)
        cachedCombinedDisplaySessions = CombinedDisplaySessionsCache(
            snapshot: snapshot,
            desktopAppSessions: desktopAppSessions,
            loadedAt: now,
            sessions: sortedSessions
        )
        return sortedSessions
    }

    private func recentActivityFallbackSessions(
        from recentEvents: [RecentSignalEvent],
        existingSessions: [SessionStatus],
        completionCutoffsBySourceKey: [String: Date],
        now: Date
    ) -> [SessionStatus] {
        let latestExistingSessionBySourceKey = Dictionary(
            grouping: existingSessions,
            by: ActivityPresentation.activitySourceKey(for:)
        ).compactMapValues { sessions in
            sessions.max(by: { lhs, rhs in lhs.updatedAt < rhs.updatedAt })
        }
        var handledSourceKeys: Set<String> = []
        var fallbackSessions: [SessionStatus] = []

        for event in recentEvents.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let sourceKey = ActivityPresentation.activitySourceKey(for: event)
            guard !handledSourceKeys.contains(sourceKey)
            else {
                continue
            }

            if let existingSession = latestExistingSessionBySourceKey[sourceKey],
               existingSession.updatedAt >= event.updatedAt,
               !Self.isPresenceSession(existingSession) {
                continue
            }

            if event.signal.displayState == .active,
               let completedAt = completionCutoffsBySourceKey[sourceKey],
               event.updatedAt <= completedAt {
                continue
            }

            guard Self.shouldUseRecentEventAsFallbackSession(event, now: now) else { continue }

            handledSourceKeys.insert(sourceKey)
            fallbackSessions.append(
                SessionStatus(
                    sessionID: "recent-activity:\(sourceKey)",
                    signal: event.signal,
                    updatedAt: event.updatedAt,
                    agent: event.agent,
                    lastEvent: event.event
                )
            )
        }

        return fallbackSessions
    }

    private func deduplicatedDisplaySessions(_ sessions: [SessionStatus]) -> [SessionStatus] {
        var sessionsBySourceKey: [String: SessionStatus] = [:]

        for session in sessions {
            let sourceKey = ActivityPresentation.activitySourceKey(for: session)
            guard let current = sessionsBySourceKey[sourceKey] else {
                sessionsBySourceKey[sourceKey] = session
                continue
            }

            if Self.shouldPreferDisplaySession(session, over: current) {
                sessionsBySourceKey[sourceKey] = session
            }
        }

        return sessionsBySourceKey.values.sorted(by: Self.displaySessionSortPrecedes)
    }

    private func deduplicatedActivitySessions(_ sessions: [SessionStatus]) -> [SessionStatus] {
        var sessionsByID: [String: SessionStatus] = [:]
        let now = Date()

        for session in sessions {
            let sessionKey = ActivityPresentation.activitySessionIdentityKey(for: session)
            guard let current = sessionsByID[sessionKey] else {
                sessionsByID[sessionKey] = session
                continue
            }

            if let merged = Self.mergedDiscoveredCodexSession(session, with: current, now: now) {
                sessionsByID[sessionKey] = merged
                continue
            }

            if Self.shouldPreferDisplaySession(session, over: current) {
                sessionsByID[sessionKey] = session
            }
        }

        return sortSessionsByStableListOrder(Array(sessionsByID.values))
    }

    private func sortSessionsByStableListOrder(_ sessions: [SessionStatus]) -> [SessionStatus] {
        let visibleIdentityKeys = Set(sessions.map(ActivityPresentation.activitySessionIdentityKey(for:)))

        stableSessionOrderByIdentityKey = stableSessionOrderByIdentityKey.filter { key, _ in
            visibleIdentityKeys.contains(key)
        }

        for session in sessions {
            let key = ActivityPresentation.activitySessionIdentityKey(for: session)
            guard stableSessionOrderByIdentityKey[key] == nil else { continue }
            stableSessionOrderByIdentityKey[key] = nextStableSessionOrder
            nextStableSessionOrder += 1
        }

        return sessions.sorted { lhs, rhs in
            let lhsKey = ActivityPresentation.activitySessionIdentityKey(for: lhs)
            let rhsKey = ActivityPresentation.activitySessionIdentityKey(for: rhs)
            let lhsOrder = stableSessionOrderByIdentityKey[lhsKey] ?? Int.max
            let rhsOrder = stableSessionOrderByIdentityKey[rhsKey] ?? Int.max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            return Self.displaySessionSortPrecedes(lhs, rhs)
        }
    }

    private static func mergedDiscoveredCodexSession(
        _ candidate: SessionStatus,
        with current: SessionStatus,
        now: Date
    ) -> SessionStatus? {
        let discoveredSession: SessionStatus
        let activitySession: SessionStatus

        if ActivityPresentation.isDiscoveredCodexIdleSession(candidate) {
            discoveredSession = candidate
            activitySession = current
        } else if ActivityPresentation.isDiscoveredCodexIdleSession(current) {
            discoveredSession = current
            activitySession = candidate
        } else {
            return nil
        }

        guard ActivityPresentation.activitySessionIdentityKey(for: discoveredSession)
            == ActivityPresentation.activitySessionIdentityKey(for: activitySession)
        else {
            return nil
        }

        if activitySession.signal.displayState == .active,
           isCurrentlyRunning(activitySession, now: now) {
            return SessionStatus(
                sessionID: discoveredSession.sessionID,
                signal: activitySession.signal,
                updatedAt: activitySession.updatedAt,
                agent: discoveredSession.agent,
                lastEvent: activitySession.lastEvent
            )
        }

        if activitySession.signal.displayState == .ready
            || activitySession.signal.displayState == .completed
            || !isCurrentlyRunning(activitySession, now: now) {
            return discoveredSession
        }

        return activitySession
    }

    private static func isCurrentlyRunning(_ session: SessionStatus, now: Date) -> Bool {
        guard session.signal.displayState == .active else { return false }
        return now.timeIntervalSince(session.updatedAt) <= activeDisplayWindow(for: session)
    }

    private static func displaySessionSortPrecedes(_ lhs: SessionStatus, _ rhs: SessionStatus) -> Bool {
        ActivityPresentation.stableSessionSortPrecedes(lhs, rhs)
    }

    private static func shouldPreferDisplaySession(_ candidate: SessionStatus, over current: SessionStatus) -> Bool {
        let candidateIsDesktopPresence = isPresenceSession(candidate)
        let currentIsDesktopPresence = isPresenceSession(current)
        if candidateIsDesktopPresence != currentIsDesktopPresence {
            if candidateIsDesktopPresence {
                return shouldPresenceOverrideStaleActivity(candidate, nonPresence: current)
            }
            if currentIsDesktopPresence {
                return !shouldPresenceOverrideStaleActivity(current, nonPresence: candidate)
            }
        }

        let candidateIsAlert = isPersistentAlert(candidate.signal.displayState)
        let currentIsAlert = isPersistentAlert(current.signal.displayState)
        if candidateIsAlert || currentIsAlert {
            let candidatePriority = deduplicationPriority(for: candidate.signal)
            let currentPriority = deduplicationPriority(for: current.signal)
            if candidatePriority != currentPriority {
                return candidatePriority > currentPriority
            }
        }

        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }

        return deduplicationPriority(for: candidate.signal) > deduplicationPriority(for: current.signal)
    }

    private static func shouldPresenceOverrideStaleActivity(
        _ presence: SessionStatus,
        nonPresence: SessionStatus
    ) -> Bool {
        guard nonPresence.signal.displayState == .active else {
            return false
        }

        return presence.updatedAt.timeIntervalSince(nonPresence.updatedAt) > activeDisplayWindow(for: nonPresence)
    }

    private static func deduplicationPriority(for signal: RuntimeSignal) -> Int {
        switch signal.displayState {
        case .blocked, .permission, .needsReview, .stale, .paused:
            return signal.displayState.priority
        case .active, .completed, .ready:
            return signal.displayState.priority
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

    static func shouldUseRecentEventAsFallbackSession(_ event: RecentSignalEvent, now: Date) -> Bool {
        if isManualIdleControlEvent(event) {
            return false
        }

        let age = now.timeIntervalSince(event.updatedAt)
        switch event.signal.displayState {
        case .active:
            return age <= recentActivityFallbackWindow(for: event)
        case .completed:
            return age <= completedDisplayWindow
        case .needsReview, .permission, .blocked, .stale:
            return true
        case .ready, .paused:
            return false
        }
    }

    private static func recentActivityFallbackWindow(for event: RecentSignalEvent) -> TimeInterval {
        isPassiveActiveEvent(event) ? passiveActiveDisplayWindow : recentActivityFallbackWindow
    }

    nonisolated static func isManualIdleControlEvent(_ event: RecentSignalEvent) -> Bool {
        event.sessionID == "manual"
            && (event.agent ?? "manual") == "manual"
            && event.signal.displayState == .ready
    }

    private static func isPassiveActiveEvent(_ event: RecentSignalEvent) -> Bool {
        guard event.signal.displayState == .active else { return false }

        switch event.event {
        case "DesktopActivityHeartbeat", "DesktopThinking":
            return true
        default:
            return false
        }
    }

    private static func latestCompletionCutoffsBySourceKey(_ events: [RecentSignalEvent]) -> [String: Date] {
        var cutoffs: [String: Date] = [:]

        for event in events where event.signal.displayState == .completed {
            let sourceKey = ActivityPresentation.activitySourceKey(for: event)
            if let existing = cutoffs[sourceKey], existing >= event.updatedAt {
                continue
            }
            cutoffs[sourceKey] = event.updatedAt
        }

        return cutoffs
    }

    private static func isSupersededByCompletedRecentEvent(
        _ session: SessionStatus,
        completionCutoffsBySourceKey: [String: Date]
    ) -> Bool {
        guard !isPresenceSession(session),
              session.signal.displayState == .active
        else {
            return false
        }

        let sourceKey = ActivityPresentation.activitySourceKey(for: session)
        guard let completedAt = completionCutoffsBySourceKey[sourceKey] else {
            return false
        }

        return completedAt >= session.updatedAt
    }

    private func deduplicatedRecentEvents(_ events: [RecentSignalEvent]) -> [RecentSignalEvent] {
        var acceptedAtByKey: [String: Date] = [:]
        var result: [RecentSignalEvent] = []

        for event in events {
            let key = Self.recentEventDeduplicationKey(for: event)
            if let acceptedAt = acceptedAtByKey[key],
               abs(acceptedAt.timeIntervalSince(event.updatedAt)) <= Self.recentEventDeduplicationWindow {
                continue
            }

            acceptedAtByKey[key] = event.updatedAt
            result.append(event)
        }

        return result
    }

    private static func recentEventDeduplicationKey(for event: RecentSignalEvent) -> String {
        let sourceKey = ActivityPresentation.activitySourceKey(for: event)
        let semanticEvent = normalizedEventDeduplicationKey(event.event, signal: event.signal)
        return "\(sourceKey)|\(semanticEvent)"
    }

    private static func normalizedEventDeduplicationKey(_ event: String?, signal: RuntimeSignal) -> String {
        guard let event,
              !event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return signal.normalizedAggregateSignal.rawValue
        }

        let normalized = event
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        if normalized.hasPrefix("desktoptoolcall:") {
            return "tool-call:\(String(normalized.dropFirst("desktoptoolcall:".count)))"
        }

        if normalized.hasPrefix("pretooluse:") {
            return "tool-call:\(String(normalized.dropFirst("pretooluse:".count)))"
        }

        if normalized.hasPrefix("posttooluse:") || normalized.hasPrefix("posttoolusefailure:") {
            return normalized.hasPrefix("posttoolusefailure:") ? "tool-failed" : "tool-done"
        }

        switch normalized {
        case "desktopthinking", "desktoptaskstarted", "userpromptsubmit":
            return "thinking"
        case "desktopmessage", "pretooluse", "tooluse", "tool-use":
            return "tool-call"
        case "desktoptooldone", "posttooluse", "posttoolbatch", "function-call-output":
            return "tool-done"
        case "desktoptaskcomplete", "desktopturnaborted", "stop", "taskcompleted":
            return "done"
        case "permissionrequest", "permission-request":
            return "permission"
        default:
            return "\(signal.normalizedAggregateSignal.rawValue):\(normalized)"
        }
    }

    var activeRuntimeSignalAgentScopes: Set<RuntimeSignalAgentScope> {
        let visibleSessions = ActivityPresentation.visibleSessions(from: activitySnapshot, limit: nil)
        return Set(
            RuntimeSignalAgentScope.selectableCases.filter { scope in
                visibleSessions.contains { scope.matches(session: $0) }
            }
        )
    }

    var displayRuntimeSignalAgentScopes: Set<RuntimeSignalAgentScope> {
        runtimeSignalAgentScopesForDisplay(from: combinedDisplaySessions())
    }

    var runtimeSignalAgentMenuTitle: String {
        displayName(for: displayRuntimeSignalAgentScopes)
    }

    var runtimeSignalAgentUnavailableHint: String? {
        guard runtimeSignalAgentSelectionMode == .manual else { return nil }

        let visibleSessions = ActivityPresentation.visibleSessions(from: activitySnapshot, limit: nil)
        let selectedHasVisibleSession = visibleSessions.contains { session in
            Self.session(session, matches: runtimeSignalAgentScopes)
        }
        guard !selectedHasVisibleSession else { return nil }

        let otherVisibleScopes = Set(
            RuntimeSignalAgentScope.selectableCases.filter { scope in
                !runtimeSignalAgentScopes.contains(scope)
                    && visibleSessions.contains { scope.matches(session: $0) }
            }
        )
        guard !otherVisibleScopes.isEmpty else { return nil }

        return text(
            "已选 Agent 尚未运行。其他 Agent 正在运行，可在灯效 Agent 中切换。",
            "The selected agent is not running. Other agents are running; switch in Light Agent if needed."
        )
    }

    private static func resolvedRuntimeSignalAgentScopes(
        storedScopes: [String]?,
        legacyScope: String?
    ) -> Set<RuntimeSignalAgentScope> {
        let selectableScopes = Set(RuntimeSignalAgentScope.selectableCases)
        let resolvedStoredScopes = Set(
            (storedScopes ?? [])
                .compactMap(RuntimeSignalAgentScope.init(rawValue:))
                .flatMap(\.expandedSelection)
        )
        .intersection(selectableScopes)

        if !resolvedStoredScopes.isEmpty {
            return resolvedStoredScopes
        }

        if let legacyScope,
           let legacySelection = RuntimeSignalAgentScope(rawValue: legacyScope) {
            let resolvedLegacyScopes = legacySelection.expandedSelection.intersection(selectableScopes)
            if !resolvedLegacyScopes.isEmpty {
                return resolvedLegacyScopes
            }
        }

        return RuntimeSignalAgentScope.defaultSelectedCases
    }

    private static func resolvedRuntimeSignalAgentSelectionMode(
        storedMode: String?,
        storedScopes: [String]?,
        legacyScope: String?
    ) -> RuntimeSignalAgentSelectionMode {
        if let storedMode,
           let mode = RuntimeSignalAgentSelectionMode(rawValue: storedMode) {
            return mode
        }

        if storedScopes != nil || legacyScope != nil {
            return .manual
        }

        return .following
    }

    private func runtimeSignalAgentScopesForDisplay(from displaySessions: [SessionStatus]) -> Set<RuntimeSignalAgentScope> {
        switch runtimeSignalAgentSelectionMode {
        case .manual:
            return runtimeSignalAgentScopes
        case .following:
            guard let scope = followedRuntimeSignalAgentScope(in: displaySessions) else {
                return []
            }
            return [scope]
        }
    }

    private func followedRuntimeSignalAgentScope(in displaySessions: [SessionStatus]) -> RuntimeSignalAgentScope? {
        struct Candidate {
            let scope: RuntimeSignalAgentScope
            let priority: Int
            let updatedAt: Date
        }

        let candidates = RuntimeSignalAgentScope.selectableCases.compactMap { scope -> Candidate? in
            let matchingSessions = displaySessions.filter {
                scope.matches(session: $0) && Self.isFollowCandidateSession($0)
            }

            guard let bestSession = matchingSessions.max(by: { lhs, rhs in
                if lhs.signal.displayState.priority != rhs.signal.displayState.priority {
                    return lhs.signal.displayState.priority < rhs.signal.displayState.priority
                }
                return lhs.updatedAt < rhs.updatedAt
            }) else {
                return nil
            }

            return Candidate(
                scope: scope,
                priority: bestSession.signal.displayState.priority,
                updatedAt: bestSession.updatedAt
            )
        }

        return candidates.max { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.scope.sortOrder > rhs.scope.sortOrder
        }?.scope
    }

    private static func isFollowCandidateSession(_ session: SessionStatus) -> Bool {
        if isSignalTestEvent(session.lastEvent) {
            return false
        }

        switch session.signal.displayState {
        case .paused:
            return false
        case .ready, .active, .completed, .needsReview, .permission, .blocked, .stale:
            return true
        }
    }

    private func aggregateForRuntimeSignalScopes(
        sessions: [SessionStatus],
        fallback: RuntimeSignal,
        scopes: Set<RuntimeSignalAgentScope>
    ) -> RuntimeSignal {
        let selectedSignals = sessions.compactMap { session -> RuntimeSignal? in
            guard Self.session(session, matches: scopes) else { return nil }
            return session.signal
        }

        if let aggregate = selectedSignals
            .max(by: { lhs, rhs in lhs.displayState.priority < rhs.displayState.priority })?
            .normalizedAggregateSignal {
            return aggregate
        }

        return fallbackForEmptyRuntimeSignalSessions(fallback, scopes: scopes)
    }

    private func aggregateForSessions(
        _ sessions: [SessionStatus],
        fallback: RuntimeSignal
    ) -> RuntimeSignal {
        if let aggregate = sessions
            .map(\.signal)
            .max(by: { lhs, rhs in lhs.displayState.priority < rhs.displayState.priority })?
            .normalizedAggregateSignal {
            return aggregate
        }

        return fallbackForEmptyDisplaySessions(fallback)
    }

    private func fallbackForEmptyDisplaySessions(_ fallback: RuntimeSignal) -> RuntimeSignal {
        switch fallback.displayState {
        case .paused, .stale, .needsReview, .permission, .blocked:
            return fallback.normalizedAggregateSignal
        case .ready, .active, .completed:
            return .idle
        }
    }

    private func fallbackForEmptyRuntimeSignalSessions(
        _ fallback: RuntimeSignal,
        scopes: Set<RuntimeSignalAgentScope>
    ) -> RuntimeSignal {
        if runtimeSignalAgentSelectionMode == .manual, !scopes.isEmpty {
            switch fallback.displayState {
            case .paused, .stale:
                return fallback.normalizedAggregateSignal
            case .ready, .active, .completed, .needsReview, .permission, .blocked:
                return .idle
            }
        }

        return fallbackForEmptyDisplaySessions(fallback)
    }

    private func sessionMatchesRuntimeSignalScopes(_ session: SessionStatus) -> Bool {
        Self.session(session, matches: runtimeSignalAgentScopes)
    }

    private func recentEventMatchesRuntimeSignalScopes(_ event: RecentSignalEvent) -> Bool {
        Self.event(event, matches: runtimeSignalAgentScopes)
    }

    private static func session(_ session: SessionStatus, matches scopes: Set<RuntimeSignalAgentScope>) -> Bool {
        scopes.contains { $0.matches(session: session) }
    }

    private static func event(_ event: RecentSignalEvent, matches scopes: Set<RuntimeSignalAgentScope>) -> Bool {
        scopes.contains { $0.matches(event: event) }
    }

    private func snapshot(_ snapshot: SignalSnapshot, overridingAggregate aggregate: RuntimeSignal) -> SignalSnapshot {
        SignalSnapshot(
            aggregate: aggregate,
            sessions: snapshot.sessions,
            recentEvents: snapshot.recentEvents,
            stateFileURL: snapshot.stateFileURL,
            updatedAt: snapshot.updatedAt
        )
    }

    private static func shouldIncludeStoredSessionInDisplay(_ session: SessionStatus, now: Date) -> Bool {
        if isSignalTestEvent(session.lastEvent) {
            return false
        }

        if isPresenceSession(session) {
            return true
        }

        switch session.signal.displayState {
        case .active:
            return now.timeIntervalSince(session.updatedAt) <= activeDisplayWindow(for: session)
        case .completed:
            return now.timeIntervalSince(session.updatedAt) <= completedDisplayWindow
        case .needsReview, .permission, .blocked, .stale:
            return true
        case .ready, .paused:
            return false
        }
    }

    private static func shouldSuppressDesktopPresence(for session: SessionStatus, now: Date) -> Bool {
        if isSignalTestEvent(session.lastEvent) {
            return false
        }

        switch session.signal.displayState {
        case .active:
            return now.timeIntervalSince(session.updatedAt) <= activeDisplayWindow(for: session)
        case .needsReview, .permission, .blocked, .stale:
            return true
        case .ready, .completed, .paused:
            return false
        }
    }

    private static func isPresenceSession(_ session: SessionStatus) -> Bool {
        session.sessionID.hasPrefix("desktop-app:")
            || session.sessionID.hasPrefix("platform-presence:")
            || session.lastEvent == "DesktopAppRunning"
            || session.lastEvent?.hasPrefix("PlatformPresence:") == true
    }

    private static func activeDisplayWindow(for session: SessionStatus) -> TimeInterval {
        isPassiveActiveSession(session) ? passiveActiveDisplayWindow : activeDisplayWindow
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

    private static func isSignalTestEvent(_ event: String?) -> Bool {
        event == "SignalTest" || event == "SignalTestOff"
    }

    private static func normalizedAgentKey(_ agent: String?, fallback: String) -> String {
        guard let agent, !agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }

        let normalized = agent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "claude", "claude-code", "claude-desktop", "claude-cli",
             "claude-terminal", "terminal-claude", "claude-ide",
             "idea-claude", "intellij-claude", "jetbrains-claude":
            return "claude"
        case "codex", "codex-desktop", "codex-cli", "codex-ide", "codex-xcode",
             "codex-terminal", "terminal-codex", "codex-tui", "codex-shell",
             "idea-codex", "intellij-codex", "jetbrains-codex", "codex-idea",
             "codex-intellij", "codex-jetbrains", "codex-vscode", "vscode-codex",
             "xcode-codex", "codex-obsidian", "obsidian-codex", "codex-acp":
            return "codex"
        default:
            return normalized
        }
    }

    private func genericAgentHookURL() -> URL? {
        bundledScriptURL(named: "generic-codex-agent-runtime-signal-hook")
    }

    private func bundledScriptURL(named scriptName: String) -> URL? {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("scripts/\(scriptName)"))
        }

        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let distParent = bundleURL.deletingLastPathComponent()
        if distParent.lastPathComponent == "dist" {
            candidates.append(
                distParent
                    .deletingLastPathComponent()
                    .appendingPathComponent("scripts/\(scriptName)")
            )
        }

        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts/\(scriptName)")
        )

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func openAgentApplication(appName: String, displayName: String) {
        let candidates = [
            URL(fileURLWithPath: "/Applications/\(appName).app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(appName).app")
        ]

        guard let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            lastError = text("没有找到 \(displayName).app。", "\(displayName).app was not found.")
            return
        }

        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        lastError = nil
    }

    private func runHookInstall(
        operation: HookInstallOperation,
        _ action: @escaping @Sendable (HookInstallManager) throws -> HookInstallResult
    ) {
        guard !isHookInstallRunning else { return }
        isHookInstallRunning = true
        hookInstallOperation = operation
        hookInstallMessage = text("正在处理 hooks...", "Processing hooks...")
        lastError = nil

        let manager = hookInstallManager
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try action(manager)
            }

            Task { @MainActor in
                self.isHookInstallRunning = false
                switch result {
                case .success(let output):
                    self.hookInstallMessage = output.displayText
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.hookInstallMessage = nil
                }
            }
        }
    }
}
