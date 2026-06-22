import CodexAgentRuntimeSignalCore
import AppKit
import Combine
import QuartzCore
import SwiftUI

enum TaskStatusBubbleKind: String, Equatable {
    case completion
    case permission

    var particleColor: Color {
        switch self {
        case .completion:
            return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .permission:
            return Color(red: 1.0, green: 0.22, blue: 0.24)
        }
    }

}

struct CompletionBubbleNotification: Equatable {
    let identityKey: String
    let kind: TaskStatusBubbleKind
    let occurredAt: Date
    let sourceApplication: String
    let sessionName: String
}

final class CompletionBubbleEventTracker {
    private var notifiedAtByKey: [String: Date] = [:]

    func prime(with candidates: [CompletionBubbleCandidate]) {
        for candidate in candidates {
            guard let notificationKey = candidate.notificationKey else { continue }
            let current = notifiedAtByKey[notificationKey] ?? .distantPast
            if candidate.updatedAt > current {
                notifiedAtByKey[notificationKey] = candidate.updatedAt
            }
        }
    }

    func notifications(from candidates: [CompletionBubbleCandidate]) -> [CompletionBubbleCandidate] {
        var latestActiveAtByIdentity: [String: Date] = [:]
        var latestNotifiableByKey: [String: CompletionBubbleCandidate] = [:]

        for candidate in candidates {
            switch candidate.signal.displayState {
            case .active:
                let current = latestActiveAtByIdentity[candidate.identityKey] ?? .distantPast
                if candidate.updatedAt > current {
                    latestActiveAtByIdentity[candidate.identityKey] = candidate.updatedAt
                }
            case .completed, .permission:
                guard let notificationKey = candidate.notificationKey else { continue }
                let current = latestNotifiableByKey[notificationKey]
                if current == nil || candidate.updatedAt > current!.updatedAt {
                    latestNotifiableByKey[notificationKey] = candidate
                }
            case .ready, .needsReview, .blocked, .stale, .paused:
                continue
            }
        }

        for (identityKey, activeAt) in latestActiveAtByIdentity {
            let keyPrefix = "\(identityKey)|"
            for (notificationKey, notifiedAt) in notifiedAtByKey where notificationKey.hasPrefix(keyPrefix) {
                if activeAt > notifiedAt {
                    notifiedAtByKey.removeValue(forKey: notificationKey)
                }
            }
        }

        return latestNotifiableByKey.values
            .filter { candidate in
                guard let notificationKey = candidate.notificationKey else { return false }
                let notifiedAt = notifiedAtByKey[notificationKey]
                let latestActiveAt = latestActiveAtByIdentity[candidate.identityKey] ?? .distantPast
                guard candidate.updatedAt > latestActiveAt else {
                    return false
                }
                if let notifiedAt,
                   latestActiveAt <= notifiedAt {
                    return false
                }
                return notifiedAt == nil || candidate.updatedAt > notifiedAt!
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return (lhs.notificationKey ?? lhs.identityKey) < (rhs.notificationKey ?? rhs.identityKey)
            }
            .map { candidate in
                if let notificationKey = candidate.notificationKey {
                    notifiedAtByKey[notificationKey] = candidate.updatedAt
                }
                return candidate
            }
    }
}

struct CompletionBubbleCandidate: Equatable {
    let identityKey: String
    let signal: RuntimeSignal
    let updatedAt: Date
    let sourceApplication: String
    let sessionName: String
    let session: SessionStatus?
    let event: String?

    init(
        identityKey: String,
        signal: RuntimeSignal,
        updatedAt: Date,
        sourceApplication: String = "",
        sessionName: String = "",
        session: SessionStatus? = nil,
        event: String? = nil
    ) {
        self.identityKey = identityKey
        self.signal = signal
        self.updatedAt = updatedAt
        self.sourceApplication = sourceApplication
        self.sessionName = sessionName
        self.session = session
        self.event = event
    }

    var notificationKind: TaskStatusBubbleKind? {
        if signal.displayState == .permission {
            return .permission
        }

        if signal.displayState == .completed,
           Self.isSuccessfulCompletionEvent(event) {
            return .completion
        }

        return nil
    }

    var notificationKey: String? {
        notificationKind.map { "\(identityKey)|\($0.rawValue)" }
    }

    private static func isSuccessfulCompletionEvent(_ event: String?) -> Bool {
        guard let event else { return true }
        let normalized = event
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        let rejectedTokens = [
            "abort",
            "aborted",
            "cancel",
            "cancelled",
            "failure",
            "failed",
            "error",
            "exception",
            "blocked",
            "denied",
            "permission",
            "max-tokens"
        ]
        return !rejectedTokens.contains { normalized.contains($0) }
    }
}

@MainActor
final class CompletionBubbleController {
    private struct ActiveBubble: @unchecked Sendable {
        let id: UUID
        let window: NSPanel
        let timer: Timer
    }

    private struct DisplayInfoCacheEntry {
        let sourceApplication: String
        let sessionName: String
        let loadedAt: Date
    }

    private let model: MenuBarStatusModel
    private let tracker = CompletionBubbleEventTracker()
    private var cancellables = Set<AnyCancellable>()
    private var activeBubbles: [ActiveBubble] = []
    private var activeSounds: [NSSound] = []
    private var displayInfoCacheByKey: [String: DisplayInfoCacheEntry] = [:]
    private var didPrime = false
    private static let visibleDuration: TimeInterval = 4
    private static let bubbleSize = NSSize(width: 246, height: 64)
    private static let stackSpacing: CGFloat = 8
    private static let topInset: CGFloat = 3
    private static let eventCandidateLookback: TimeInterval = 2 * 60
    private static let displayInfoCacheTTL: TimeInterval = 30

    init(model: MenuBarStatusModel) {
        self.model = model
        bind()
    }

    func start() {
        evaluate(snapshot: model.snapshot)
    }

    func applyAppearance() {
        let appearance = model.appTheme.nsAppearance
        for bubble in activeBubbles {
            bubble.window.appearance = appearance
            bubble.window.contentView?.appearance = appearance
        }
    }

    private func bind() {
        model.$snapshot.sink { [weak self] snapshot in
            Task { @MainActor in
                self?.evaluate(snapshot: snapshot)
            }
        }
        .store(in: &cancellables)

        model.$completionBubbleCompletionSoundTestTick.dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playSound(self.model.completionBubbleCompletionSound)
            }
        }
        .store(in: &cancellables)

        model.$completionBubblePermissionSoundTestTick.dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playSound(self.model.completionBubblePermissionSound)
            }
        }
        .store(in: &cancellables)

        model.$appTheme.sink { [weak self] _ in
            Task { @MainActor in
                self?.applyAppearance()
            }
        }
        .store(in: &cancellables)
    }

    private func evaluate(snapshot: SignalSnapshot) {
        let candidates = completionCandidates(from: snapshot)
        guard didPrime else {
            tracker.prime(with: candidates)
            didPrime = true
            return
        }

        let notifications = tracker.notifications(from: candidates)
        guard !notifications.isEmpty else { return }
        guard model.isCompletionBubbleEnabled else { return }

        for notification in notifications {
            let displayInfo = displayInfo(for: notification)
            showBubble(
                CompletionBubbleNotification(
                    identityKey: notification.identityKey,
                    kind: notification.notificationKind ?? .completion,
                    occurredAt: notification.updatedAt,
                    sourceApplication: displayInfo.sourceApplication,
                    sessionName: displayInfo.sessionName
                )
            )
            playSound(sound(for: notification.notificationKind ?? .completion))
        }
    }

    private func completionCandidates(from snapshot: SignalSnapshot) -> [CompletionBubbleCandidate] {
        let eventCutoff = Date().addingTimeInterval(-Self.eventCandidateLookback)
        let sessionCandidates = snapshot.sessions.map { candidate(from: $0) }
        let eventCandidates = snapshot.recentEvents
            .lazy
            .filter { $0.updatedAt >= eventCutoff }
            .map { event in
                self.candidate(
                    from: SessionStatus(
                        sessionID: event.sessionID,
                        signal: event.signal,
                        updatedAt: event.updatedAt,
                        agent: event.agent,
                        lastEvent: event.event
                    )
                )
            }
        return sessionCandidates + eventCandidates
    }

    private func candidate(from session: SessionStatus) -> CompletionBubbleCandidate {
        CompletionBubbleCandidate(
            identityKey: ActivityPresentation.activitySessionIdentityKey(for: session),
            signal: session.signal,
            updatedAt: session.updatedAt,
            session: session,
            event: session.lastEvent
        )
    }

    private func displayInfo(for candidate: CompletionBubbleCandidate) -> (sourceApplication: String, sessionName: String) {
        if let session = candidate.session {
            let cacheKey = displayInfoCacheKey(for: session)
            let now = Date()
            if let cached = displayInfoCacheByKey[cacheKey],
               now.timeIntervalSince(cached.loadedAt) < Self.displayInfoCacheTTL {
                return (cached.sourceApplication, cached.sessionName)
            }

            pruneDisplayInfoCache(now: now)
            let displayInfo = (
                model.activitySessionSourceTitle(for: session),
                model.activitySessionName(for: session)
            )
            displayInfoCacheByKey[cacheKey] = DisplayInfoCacheEntry(
                sourceApplication: displayInfo.0,
                sessionName: displayInfo.1,
                loadedAt: now
            )
            return displayInfo
        }

        return (
            candidate.sourceApplication.isEmpty ? "Codex" : candidate.sourceApplication,
            candidate.sessionName.isEmpty ? model.text("未命名会话", "Unnamed session") : candidate.sessionName
        )
    }

    private func displayInfoCacheKey(for session: SessionStatus) -> String {
        "\(session.sessionID)|\(session.agent ?? "")"
    }

    private func pruneDisplayInfoCache(now: Date) {
        displayInfoCacheByKey = displayInfoCacheByKey.filter { _, entry in
            now.timeIntervalSince(entry.loadedAt) < Self.displayInfoCacheTTL
        }
    }

    private func showBubble(_ notification: CompletionBubbleNotification) {
        let id = UUID()
        let view = CompletionBubbleView(
            size: Self.bubbleSize,
            kind: notification.kind,
            title: title(for: notification.kind),
            sourceApplication: notification.sourceApplication,
            sessionName: notification.sessionName,
            dismiss: { [weak self] in
                self?.dismissBubble(id)
            }
        )
        let hostingController = NSHostingController(rootView: view)
        let windowSize = Self.bubbleSize
        hostingController.view.frame = NSRect(origin: .zero, size: windowSize)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.appearance = model.appTheme.nsAppearance
        window.contentViewController = hostingController
        window.setContentSize(windowSize)
        window.alphaValue = 0

        let timer = Timer(timeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissBubble(id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        activeBubbles.append(ActiveBubble(id: id, window: window, timer: timer))
        layoutBubbles()
        window.orderFrontRegardless()
        layoutBubbles(animated: false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
    }

    private func dismissBubble(_ id: UUID) {
        guard let index = activeBubbles.firstIndex(where: { $0.id == id }) else { return }
        let bubble = activeBubbles.remove(at: index)
        bubble.timer.invalidate()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            bubble.window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                bubble.window.close()
            }
        }
        layoutBubbles()
    }

    private func layoutBubbles(animated: Bool = true) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let centerX = screen.frame.midX
        let notchBottomY = screen.frame.maxY - screen.safeAreaInsets.top
        let visibleTopY = screen.visibleFrame.maxY
        var nextTopY = min(notchBottomY, visibleTopY) - Self.topInset

        for bubble in activeBubbles {
            let size = Self.bubbleSize
            let origin = NSPoint(
                x: centerX - size.width / 2,
                y: nextTopY - size.height
            )
            bubble.window.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
            nextTopY = origin.y - Self.stackSpacing
        }
    }

    private func title(for kind: TaskStatusBubbleKind) -> String {
        switch kind {
        case .completion:
            return model.text("任务已完成", "Task completed")
        case .permission:
            return model.text("等待权限确认", "Waiting for permission")
        }
    }

    private func sound(for kind: TaskStatusBubbleKind) -> TaskStatusBubbleSound {
        switch kind {
        case .completion:
            return model.completionBubbleCompletionSound
        case .permission:
            return model.completionBubblePermissionSound
        }
    }

    private func playSound(_ soundPreference: TaskStatusBubbleSound) {
        guard let soundName = soundPreference.soundName else { return }
        let url = Bundle.main.url(
            forResource: soundName,
            withExtension: "aiff",
            subdirectory: nil
        ) ?? URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            NSSound.beep()
            return
        }

        sound.volume = 0.75
        activeSounds.append(sound)
        if sound.play() != true {
            NSSound.beep()
            activeSounds.removeAll { $0 === sound }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak sound] in
            guard let sound else { return }
            self?.activeSounds.removeAll { $0 === sound }
        }
    }
}

private struct CompletionBubbleView: View {
    let size: NSSize
    let kind: TaskStatusBubbleKind
    let title: String
    let sourceApplication: String
    let sessionName: String
    let dismiss: () -> Void

    private let bubbleFill = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.22, blue: 0.25),
            Color(red: 0.10, green: 0.11, blue: 0.13)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private let titleColor = Color(red: 0.96, green: 0.97, blue: 0.99)
    private let secondaryColor = Color(red: 0.78, green: 0.82, blue: 0.88)
    private let bodyColor = Color(red: 0.88, green: 0.91, blue: 0.96)

    var body: some View {
        Button(action: dismiss) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(bubbleFill)
                CompletionBubbleParticleField(tint: kind.particleColor)
                    .clipShape(Capsule(style: .continuous))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    MarqueeText(
                        text: sourceApplication,
                        fontSize: 10,
                        weight: .semibold,
                        color: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.88, alpha: 1)
                    )
                    .frame(height: 12)
                    MarqueeText(
                        text: sessionName,
                        fontSize: 10,
                        weight: .medium,
                        color: NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.96, alpha: 1)
                    )
                    .frame(height: 13)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MarqueeText: View {
    let text: String
    let fontSize: CGFloat
    let weight: NSFont.Weight
    let color: NSColor

    var body: some View {
        MarqueeTextRepresentable(
            text: text,
            font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            color: color
        )
    }
}

private struct MarqueeTextRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor

    func makeNSView(context: Context) -> MarqueeLabelView {
        MarqueeLabelView()
    }

    func updateNSView(_ view: MarqueeLabelView, context: Context) {
        view.configure(text: text, font: font, color: color)
    }
}

private final class MarqueeLabelView: NSView {
    private let textLayer = CATextLayer()
    private var currentText = ""
    private var currentFont = NSFont.systemFont(ofSize: 10)
    private var currentColor = NSColor.white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.alignmentMode = .left
        textLayer.truncationMode = .none
        textLayer.isWrapped = false
        layer?.addSublayer(textLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(text: String, font: NSFont, color: NSColor) {
        let changed = currentText != text || currentFont != font || currentColor != color
        currentText = text
        currentFont = font
        currentColor = color
        textLayer.string = text
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = color.cgColor
        if changed {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        layoutTextLayer()
    }

    private func layoutTextLayer() {
        let attributes: [NSAttributedString.Key: Any] = [.font: currentFont]
        let textWidth = ceil((currentText as NSString).size(withAttributes: attributes).width)
        let lineHeight = ceil(currentFont.ascender - currentFont.descender + currentFont.leading)
        let y = floor((bounds.height - lineHeight) / 2)

        textLayer.removeAnimation(forKey: "marquee")
        textLayer.frame = CGRect(x: 0, y: y, width: max(textWidth, bounds.width), height: lineHeight)

        let overflow = textWidth - bounds.width
        guard overflow > 2 else { return }

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -overflow
        animation.duration = min(max(Double(overflow / 42), 1.4), 2.7)
        animation.beginTime = CACurrentMediaTime() + 0.35
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        textLayer.add(animation, forKey: "marquee")
    }
}

private struct CompletionBubbleParticleField: View {
    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let side: CGFloat
        let residualOpacity: Double
    }

    let tint: Color
    @State private var isExpanded = false
    private static let particles: [Particle] = (0..<18).map { index in
        let angle = Double(index) * 2.399963 + Double(index % 5) * 0.17
        let spread = CGFloat(20 + (index % 6) * 8)
        return Particle(
            id: index,
            x: CGFloat(cos(angle)) * spread,
            y: CGFloat(sin(angle)) * spread * 0.34,
            side: CGFloat(2.0 + Double(index % 3)),
            residualOpacity: 0.07 + Double(index % 4) * 0.018
        )
    }

    var body: some View {
        ZStack {
            ForEach(Self.particles) { particle in
                Circle()
                    .fill(tint.opacity(isExpanded ? particle.residualOpacity : 0.78))
                    .frame(width: particle.side, height: particle.side)
                    .offset(
                        x: isExpanded ? particle.x : 0,
                        y: isExpanded ? particle.y : 0
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                isExpanded = true
            }
        }
    }
}
