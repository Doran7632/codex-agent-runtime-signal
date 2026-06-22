# Claude Code Setup

Claude Code hook 事件建议映射：

| Claude Code event | Signal |
| --- | --- |
| `ConfigChange` | `attention` |
| `CwdChanged` | `attention` |
| `Elicitation` | `attention` |
| `ElicitationResult` | `working` |
| `FileChanged` | `attention` |
| `InstructionsLoaded` | `attention` |
| `SessionStart` | `session_start` |
| `TaskCreated` | `subagent_start` |
| `TaskCompleted` | `subagent_stop` |
| `TeammateIdle` | `idle` |
| `UserPromptExpansion` | `thinking` |
| `UserPromptSubmit` | `thinking` |
| `PreToolUse` | `working` |
| `PostToolBatch` | `tool_done` |
| `PostToolUse` | `tool_done` |
| `PostToolUseFailure` | `blocked` |
| `PreCompact` | `working` |
| `PostCompact` | `tool_done` |
| `SubagentStart` | `subagent_start` |
| `SubagentStop` | `subagent_stop` |
| `PermissionRequest` | `permission_request` |
| `PermissionDenied` | `blocked` |
| `Notification` | `notification` |
| `Stop` | `done` |
| `StopFailure` | `blocked` |
| `WorktreeCreate` | `working` |
| `WorktreeRemove` | `attention` |
| `SessionEnd` | `session_end` |

普通 `Stop` 表示成功完成，会进入短暂的绿色 completed。紧随其后的 `SessionEnd` 会保留 completed 和需要处理的提示，只清理普通 active session。若当前 session 已经是 `permission`、`blocked` 或 `attention`，这个完成事件只会写入最近事件，不会覆盖仍需处理的提示。如果 hook payload 中包含 `error`、`failure`、`exception`、非零 `exit_status` 等结构化失败字段，即使事件名不是 `PostToolUseFailure`，也会映射为 `blocked`。

事件名会做容错归一化，`PostToolUseFailure`、`post_tool_use_failure`、`post-tool-use-failure` 和 `post tool use failure` 都会映射到同一个 signal。
常见 payload 字段名也会容错归一化，例如 `session_id` / `sessionId`、`hook_event_name` / `hookEventName`、`exit_status` / `exitStatus`、`stop_reason` / `stopReason`。

`Stop` 的 `stop_reason` 也会做容错归一化：`max_tokens`、`max-tokens`、`max tokens` 都会映射为 `max_tokens` 阻塞；包含 `error` / `failure` / `exception` 的原因会映射为红色错误。

Claude Code 会把事件 JSON 传给 hook stdin，因此通常不需要把事件名作为命令参数。

## Desktop App vs Claude Code

codex-agent-runtime-signal 的 `thinking` / `working` / `done` 状态来自 Claude Code hook 事件，例如 `UserPromptSubmit`、`PreToolUse` 和 `Stop`。Claude Desktop 的普通聊天窗口只表示 Claude.app 正在运行，不会把这些 Claude Code hook 事件发给 `~/.claude/settings.json`。

如果设置窗口显示 hook 已配置，但 Claude 仍然只显示“桌面版运行中”，先运行：

```bash
./script/doctor.sh
```

重点看两项：

- `Claude Code CLI not found in PATH`：当前终端环境没有可运行的 `claude` 命令，无法用 CLI 会话触发 hook。
- `Claude Desktop log says Claude Code requires a Pro or Max subscription`：Claude Desktop 没能启动 Claude Code/local-agent runtime；在这个状态下，普通 Claude 聊天不会产生 `thinking` / `working` hook 事件。

## Recommended Install

先安装 release 版 CLI，避免 hook 第一次触发时临时编译：

```bash
./script/install_cli.sh
```

预览并合并到现有 `~/.claude/settings.json`：

```bash
./script/install_hooks.py --target claude --dry-run
./script/install_hooks.py --target claude --install
```

安装脚本会保留已有 JSON 字段，只追加缺失的 codex-agent-runtime-signal hook block，并在写入已有文件前生成 `settings.json.bak-YYYYmmddHHMMSS` 备份。如果发现旧路径的 `claude-code-signal-hook`，会迁移到当前 checkout 或当前 app bundle 的 wrapper 路径，避免同一个事件重复触发多个 codex-agent-runtime-signal hook。

## Manual Shape

通常不需要手写 JSON。若要手动配置，command 中的 wrapper 路径必须 shell-safe；路径含空格时要用单引号包住：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'/path/to/CodexAgentRuntimeSignal/scripts/claude-code-signal-hook'",
            "timeout": 5
          }
        ],
        "matcher": ""
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'/path/to/CodexAgentRuntimeSignal/scripts/claude-code-signal-hook'",
            "timeout": 10
          }
        ],
        "matcher": ""
      }
    ]
  }
}
```

完整事件列表以 `./script/install_hooks.py --target claude --dry-run` 输出为准。
