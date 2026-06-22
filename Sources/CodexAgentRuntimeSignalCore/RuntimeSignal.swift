import Foundation

public enum DisplayState: String, Codable, CaseIterable, Sendable {
    case ready
    case active
    case completed
    case needsReview = "needs_review"
    case permission
    case blocked
    case stale
    case paused

    public var priority: Int {
        switch self {
        case .paused:
            return 100
        case .blocked:
            return 90
        case .permission:
            return 80
        case .needsReview:
            return 70
        case .stale:
            return 60
        case .active:
            return 50
        case .completed:
            return 40
        case .ready:
            return 0
        }
    }

    public var humanAction: String {
        switch self {
        case .ready, .active, .completed:
            return "不用处理"
        case .needsReview:
            return "有空看一眼"
        case .permission, .blocked:
            return "马上处理"
        case .stale:
            return "确认状态"
        case .paused:
            return "监控已暂停"
        }
    }
}

public typealias LampState = DisplayState

public enum RuntimeSignal: String, Codable, CaseIterable, Sendable {
    case idle
    case thinking
    case working
    case toolDone = "tool_done"
    case subagentStart = "subagent_start"
    case subagentStop = "subagent_stop"
    case attention
    case notification
    case done
    case permission
    case permissionRequest = "permission_request"
    case blocked
    case failure
    case error
    case exception
    case maxTokens = "max_tokens"
    case stale
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case turnEnd = "turn_end"
    case off
    case pause
    case paused

    public static func normalized(_ rawValue: String) -> RuntimeSignal? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "tooluse", "tool_use", "pre_tool_use":
            return .working
        case "post_tool_use":
            return .toolDone
        case "subagentstart":
            return .subagentStart
        case "subagentstop":
            return .subagentStop
        case "permissionrequest":
            return .permissionRequest
        case "failed":
            return .failure
        case "maxtokens":
            return .maxTokens
        default:
            break
        }
        return RuntimeSignal(rawValue: normalized)
    }

    public var displayState: DisplayState {
        switch self {
        case .idle, .sessionStart, .sessionEnd, .turnEnd:
            return .ready
        case .thinking, .working, .toolDone, .subagentStart, .subagentStop:
            return .active
        case .done:
            return .completed
        case .attention, .notification:
            return .needsReview
        case .permission, .permissionRequest:
            return .permission
        case .blocked, .failure, .error, .exception, .maxTokens:
            return .blocked
        case .stale:
            return .stale
        case .off, .pause, .paused:
            return .paused
        }
    }

    public var lampState: LampState {
        displayState
    }

    public var normalizedAggregateSignal: RuntimeSignal {
        switch displayState {
        case .ready:
            return .idle
        case .active:
            return self
        case .completed:
            return .done
        case .needsReview:
            return .attention
        case .permission:
            return .permission
        case .blocked:
            return .blocked
        case .stale:
            return .stale
        case .paused:
            return .off
        }
    }

    public var displayName: String {
        switch self {
        case .idle:
            return "空闲"
        case .thinking:
            return "思考中"
        case .working:
            return "工作中"
        case .toolDone:
            return "步骤完成"
        case .subagentStart:
            return "子 Agent 开始"
        case .subagentStop:
            return "子 Agent 完成"
        case .attention:
            return "需要查看"
        case .notification:
            return "通知"
        case .done:
            return "已完成"
        case .permission:
            return "请求授权"
        case .permissionRequest:
            return "等待授权"
        case .blocked:
            return "阻塞/失败"
        case .failure:
            return "失败"
        case .error:
            return "错误"
        case .exception:
            return "异常"
        case .maxTokens:
            return "上下文阻塞"
        case .stale:
            return "状态不可信"
        case .sessionStart:
            return "会话开始"
        case .sessionEnd:
            return "会话结束"
        case .turnEnd:
            return "回合结束"
        case .off:
            return "已关闭"
        case .pause, .paused:
            return "已暂停"
        }
    }

    public var summary: String {
        switch self {
        case .idle, .sessionStart, .sessionEnd, .turnEnd:
            return "Agent 空闲。"
        case .thinking:
            return "Agent 已收到任务，正在思考。"
        case .working:
            return "Agent 正在读写文件、跑工具或测试。"
        case .toolDone:
            return "一个步骤已完成，Agent 仍在工作流中。"
        case .subagentStart:
            return "子 Agent 正在运行。"
        case .subagentStop:
            return "子 Agent 已完成，主工作流仍可能继续。"
        case .attention:
            return "Agent 明确需要你看一眼或继续。"
        case .notification:
            return "Agent 发出了需要查看的通知。"
        case .done:
            return "任务完成。"
        case .permission:
            return "Agent 正在请求权限或明确批准。"
        case .permissionRequest:
            return "Agent 正在等待用户授权。"
        case .blocked:
            return "Agent 遇到失败、阻塞或无法继续。"
        case .failure:
            return "Agent 或工具报告失败。"
        case .error:
            return "Agent 或工具报告错误。"
        case .exception:
            return "Agent 或工具报告异常。"
        case .maxTokens:
            return "Agent 因上下文或 token 限制无法继续。"
        case .stale:
            return "状态文件过期、损坏，或当前状态不可信。"
        case .off:
            return "监控已暂停。"
        case .pause, .paused:
            return "监控已暂停。"
        }
    }

    public var humanAction: String {
        displayState.humanAction
    }

    public var priority: Int {
        displayState.priority
    }
}

public extension RuntimeSignal {
    static let redSignals: Set<RuntimeSignal> = [
        .permission, .permissionRequest, .blocked, .failure, .error, .exception, .maxTokens
    ]
    static let yellowSignals: Set<RuntimeSignal> = [.attention, .notification]
    static let workingSignals: Set<RuntimeSignal> = [
        .thinking, .working, .toolDone, .subagentStart, .subagentStop
    ]
    static let sessionEndSignals: Set<RuntimeSignal> = [.sessionEnd, .off, .pause, .paused]

    var blocksTurnEndClear: Bool {
        displayState == .permission || displayState == .blocked
    }

}
