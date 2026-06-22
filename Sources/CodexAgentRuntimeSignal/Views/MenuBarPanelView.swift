import CodexAgentRuntimeSignalCore
import CodexAgentRuntimeSignalUI
import AppKit
import Combine
import SwiftUI

struct MenuBarPanelView: View {
    static let panelWidth: CGFloat = 304
    static let minimumPanelHeight: CGFloat = 372
    private static let contentInset: CGFloat = 16
    private static let actionColumnSpacing: CGFloat = 8

    let model: MenuBarStatusModel
    var onOpenSettings: (() -> Void)?
    @StateObject private var viewState: MenuBarPanelViewState
    @Environment(\.colorScheme) private var colorScheme

    init(model: MenuBarStatusModel, onOpenSettings: (() -> Void)? = nil) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        _viewState = StateObject(wrappedValue: MenuBarPanelViewState(model: model))
    }

    var body: some View {
        ZStack {
            PopoverBackdropView()
                .ignoresSafeArea()
                .zIndex(0)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    statusSummary

                    if let lastError = viewState.lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Self.contentInset)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(width: Self.panelWidth, alignment: .leading)
                .contentShape(Rectangle())
                .zIndex(0)

                Divider()
                    .padding(.horizontal, Self.contentInset)
                    .zIndex(0)

                mainActions
                    .padding(.horizontal, Self.contentInset)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .frame(width: Self.panelWidth, alignment: .leading)
                    .zIndex(1)
            }
        }
        .frame(width: Self.panelWidth)
        .preferredColorScheme(viewState.appTheme.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 12) {
            PanelTrafficSignalView(model: model)

            VStack(alignment: .leading, spacing: 2) {
                Text("codex-agent-runtime-signal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.displayName(for: viewState.lightSnapshot.aggregate))
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.80)
                Text(model.humanAction(for: viewState.lightSnapshot.aggregate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.80)
            }

            Spacer()
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.summary(for: viewState.lightSnapshot.aggregate))
                .font(.subheadline)
                .lineLimit(2)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let updatedAt = viewState.snapshot.updatedAt {
                    Text("\(model.text("实时", "Live")) \(updatedAt.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text(model.text("等待状态", "Waiting for status"))
                }

                if viewState.isMonitoringPaused {
                    Text(model.text("已暂停", "Paused"))
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if visibleAgentSessions.isEmpty {
                Text(model.text("暂无运行中的 Agent", "No active agent sessions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleAgentSessions) { session in
                        SessionRowView(model: model, session: session)
                    }
                }
            }

        }
    }

    private var visibleAgentSessions: [SessionStatus] {
        ActivityPresentation.visibleSessions(
            from: viewState.activitySnapshot,
            limit: nil
        )
    }

    private var mainActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.actionColumnSpacing) {
                Button {
                    model.toggleMonitoring()
                } label: {
                    actionSurface(
                        viewState.isMonitoringPaused ? model.text("继续监控", "Resume") : model.text("暂停监控", "Pause"),
                        systemImage: viewState.isMonitoringPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.plain)
                .frame(width: actionButtonWidth, height: actionButtonHeight)

                Button {
                    onOpenSettings?()
                } label: {
                    actionSurface(model.text("设置", "Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .frame(width: actionButtonWidth, height: actionButtonHeight)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(model.text("退出", "Quit"), systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var actionButtonWidth: CGFloat {
        (Self.panelWidth - Self.contentInset * 2 - Self.actionColumnSpacing) / 2
    }

    private var actionButtonHeight: CGFloat {
        28
    }

    private var panelActionFont: Font {
        .system(size: usesCompactLatinLayout ? 12 : 13, weight: .semibold)
    }

    private var usesCompactLatinLayout: Bool {
        viewState.appLanguage.usesCompactLatinLayout
    }

    private func actionSurface(
        _ title: String,
        systemImage: String,
        showsChevron: Bool = false,
        isExpanded: Bool = false,
        width: CGFloat? = nil
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)

            Text(title)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.72)

            if showsChevron {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 10)
            }
        }
        .font(panelActionFont)
        .foregroundStyle(.primary)
        .frame(width: width ?? actionButtonWidth, height: actionButtonHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(panelMenuBarFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(solidControlStroke, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var panelMenuBarFill: some ShapeStyle {
        .tertiary.opacity(0.08)
    }

    private var solidControlStroke: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.34, alpha: 1))
            : Color(nsColor: NSColor(calibratedWhite: 0.78, alpha: 1))
    }

}

@MainActor
private final class MenuBarPanelViewState: ObservableObject {
    @Published var snapshot: SignalSnapshot
    @Published var lightSnapshot: SignalSnapshot
    @Published var activitySnapshot: SignalSnapshot
    @Published var appTheme: AppTheme
    @Published var isMonitoringPaused: Bool
    @Published var lastError: String?
    @Published var appLanguage: AppLanguage

    private var cancellables = Set<AnyCancellable>()

    init(model: MenuBarStatusModel) {
        snapshot = model.displaySnapshot
        lightSnapshot = model.lightSnapshot
        activitySnapshot = model.activitySnapshot
        appTheme = model.appTheme
        isMonitoringPaused = model.isMonitoringPaused
        lastError = model.lastError
        appLanguage = model.appLanguage

        model.$snapshot
            .sink { [weak self, weak model] _ in
                guard let model else { return }
                self?.refreshSnapshots(from: model)
            }
            .store(in: &cancellables)

        model.$desktopAppSessions
            .sink { [weak self, weak model] _ in
                guard let model else { return }
                self?.refreshSnapshots(from: model)
            }
            .store(in: &cancellables)

        model.$runtimeSignalAgentScopes
            .sink { [weak self, weak model] _ in
                guard let model else { return }
                self?.refreshSnapshots(from: model)
            }
            .store(in: &cancellables)

        model.$runtimeSignalAgentSelectionMode
            .sink { [weak self, weak model] _ in
                guard let model else { return }
                self?.refreshSnapshots(from: model)
            }
            .store(in: &cancellables)

        model.$statusLightOverride
            .sink { [weak self, weak model] _ in
                guard let model else { return }
                self?.refreshSnapshots(from: model)
            }
            .store(in: &cancellables)

        model.$appTheme
            .removeDuplicates()
            .sink { [weak self] appTheme in
                self?.appTheme = appTheme
            }
            .store(in: &cancellables)

        model.$isMonitoringPaused
            .removeDuplicates()
            .sink { [weak self, weak model] isMonitoringPaused in
                self?.isMonitoringPaused = isMonitoringPaused
                guard let model else { return }
                self?.refreshSnapshots(from: model)
            }
            .store(in: &cancellables)

        model.$lastError
            .removeDuplicates()
            .sink { [weak self] lastError in
                self?.lastError = lastError
            }
            .store(in: &cancellables)

        model.$appLanguage
            .removeDuplicates()
            .sink { [weak self] appLanguage in
                self?.appLanguage = appLanguage
            }
            .store(in: &cancellables)
    }

    private func refreshSnapshots(from model: MenuBarStatusModel) {
        snapshot = model.displaySnapshot
        lightSnapshot = model.lightSnapshot
        activitySnapshot = model.activitySnapshot
    }
}

private struct PanelTrafficSignalView: View {
    @ObservedObject var model: MenuBarStatusModel
    @ObservedObject private var animationClock: SignalAnimationClock

    init(model: MenuBarStatusModel) {
        self.model = model
        _animationClock = ObservedObject(wrappedValue: model.animationClock)
    }

    var body: some View {
        TrafficSignalView(
            snapshot: model.lightSnapshot,
            tick: model.lightTick,
            size: .panel,
            layout: .horizontal,
            style: model.statusBarStyle,
            macOSBreathingStrength: model.macOSBreathingStrength,
            macOSHorizontalUsesTrafficLightSize: model.macOSHorizontalUsesTrafficLightSize,
            trafficLightVerticalUsesMacOSSize: model.trafficLightVerticalUsesMacOSSize,
            allLightsOn: model.lightAllLightsOn,
            usesSystemGrayLights: model.lightUsesSystemGrayLights,
            effectCustomization: model.lightEffectCustomization
        )
    }
}

private struct PopoverBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

private struct SessionRowView: View {
    let model: MenuBarStatusModel
    let session: SessionStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(signalColor(session.signal))
                .frame(width: 7, height: 7)

            Text(displayLine)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(displayLine)

            Spacer()
        }
    }

    private var displayLine: String {
        model.activitySessionLine(for: session)
    }
}

private func signalColor(_ signal: RuntimeSignal) -> Color {
    switch signal.displayState {
    case .ready, .active, .completed:
        return Color(red: 0.16, green: 0.78, blue: 0.34)
    case .needsReview:
        return Color(red: 0.97, green: 0.72, blue: 0.16)
    case .permission, .blocked:
        return Color(red: 0.94, green: 0.20, blue: 0.18)
    case .stale, .paused:
        return .secondary
    }
}
