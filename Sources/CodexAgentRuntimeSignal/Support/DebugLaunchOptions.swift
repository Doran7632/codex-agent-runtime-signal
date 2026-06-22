import Foundation

enum DebugLaunchOptions {
    static var shouldOpenDebugWindow: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--debug-window") || arguments.contains("--ui-verify") {
            return true
        }

        let rawValue = ProcessInfo.processInfo.environment["CODEX_AGENT_RUNTIME_SIGNAL_DEBUG_WINDOW"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["1", "true", "yes", "on"].contains(rawValue) {
            return true
        }

        return isStatusBarIconPersistentlyDisabled && !shouldForceStatusBarIconEnabled
    }

    static var shouldForceStatusBarIconEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--force-status-bar-icon") {
            return true
        }

        let rawValue = ProcessInfo.processInfo.environment["CODEX_AGENT_RUNTIME_SIGNAL_FORCE_STATUS_BAR_ICON"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes", "on"].contains(rawValue)
    }

    static let statusItemHealthFileURL: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--status-item-health"),
           arguments.indices.contains(arguments.index(after: index)) {
            return URL(fileURLWithPath: arguments[arguments.index(after: index)])
        }

        guard let rawValue = ProcessInfo.processInfo.environment["CODEX_AGENT_RUNTIME_SIGNAL_STATUS_ITEM_HEALTH_FILE"],
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: rawValue)
    }()

    private static var isStatusBarIconPersistentlyDisabled: Bool {
        UserDefaults.standard.object(forKey: "isStatusBarIconEnabled") as? Bool == false
    }
}
