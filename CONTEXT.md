# Agent Activity Context

## Terms

- **Session row**: One visible row in the live activity area. It represents exactly one agent session, not an aggregated source such as all Codex CLI sessions.
- **Source application**: The host application where a session is running, such as IDEA, desktop terminal, VS Code, Xcode, or Codex Desktop.
- **Session name**: The human-facing identifier shown in parentheses after the status so the user can distinguish multiple Codex sessions.
- **Codex thread name**: The name shown by `codex resume`. It comes from Codex's `session_index.jsonl` `thread_name`, reflects explicit rename commands when present, and otherwise defaults to the session's first user question.
- **Completion bubble**: A new, independent visual and sound notification shown when any one agent session finishes. It is separate from the existing floating signal, status menu, and existing sound preferences.
- **Floating signal**: The old always-on floating window feature. It is no longer part of the product direction because the app should stay small, low-energy, and primarily menu-bar based.

## Decisions

- The live activity area displays one row per session. Multiple sessions from the same source application remain separate rows.
- The session name for Codex rows should use the Codex thread name. If the session has not been renamed, show the default first-question name.
- Source applications can repeat across rows. Multiple sessions from IDEA or desktop terminal are shown as separate rows with the same source application label and different session names.
- The live activity area is not capped by a fixed row count. It should show every visible session and let the panel expand to fit them.
- Session rows use a single-line format: `Source application - Status - (Session name)`.
- If a Codex thread name cannot be resolved, show `未命名会话` instead of an internal session id.
- The live activity area only shows currently opened Codex sessions. Codex's resume index and rollout history are lookup sources for session names and host metadata; they are not standalone rows.
- Open Codex sessions are proven by live processes holding rollout files. `turn-ended` Computer Use records are history, not open-session proof.
- Obsidian-hosted Codex can appear as `codex-acp`; when its parent chain includes `Obsidian.app`, the source application label is `Obsidian`.
- A completion bubble is triggered per finished session. If six sessions are running and one finishes, that one finished session should show a bubble and play the completion-bubble sound without waiting for the other sessions.
- Completion bubbles must be implemented as a separate feature path, not as reuse or configuration of the existing floating signal bubbles/sounds.
- A completion bubble uses three lines: completion title, source application, and session name. The source application and session name reuse the same labels shown in the live session row.
- A completion bubble stays visible for 4 seconds, fades out automatically, and can be dismissed immediately by clicking the bubble.
- Completion bubbles are positioned directly below the MacBook notch. If multiple sessions complete at the same time, completion bubbles are shown concurrently in a vertical stack below the notch, ordered from top to bottom. Each completed session plays the completion-bubble sound once.
- If the display has no notch or the notch cannot be detected, completion bubbles fall back to the top center of the main screen, below the menu bar.
- Completion bubble sound is independent from existing floating signal sounds. It is enabled by default and uses the macOS `Glass` system sound by default.
- Completion bubble notifications have their own settings, independent from existing floating signal settings: bubble enabled defaults to on, and bubble sound enabled defaults to on.
- Clicking a completion bubble only dismisses that bubble. It does not open the status menu, switch applications, or navigate to the session.
- A session completion should show and sound only once for a single completion transition. Repeated refreshes of the same completed state must not retrigger the bubble. If the same session later becomes running/thinking again and then completes again, it may trigger another bubble.
- Task status bubbles have two notification kinds: a normal completion bubble with blue particles, and a permission-stuck bubble with red particles.
- Completion bubbles should trigger only for normal successful completion, not aborted, failed, blocked, or error endings.
- Permission-stuck bubbles should trigger when a session is waiting on permission, using the same bubble surface but red particle styling.
- The task status bubble particle effect bursts when the bubble appears, then remains as a subtle lightweight particle motion until the bubble disappears.
- A permission-stuck bubble title is `等待权限确认` in Chinese and `Waiting for permission` in English.
- Completion bubbles use the Glass system sound; permission-stuck bubbles use the Ping system sound.
- Task status bubble sounds are configurable per notification kind. Completion and permission-stuck bubbles have separate sound choices, and either kind can be set to off without affecting the other.
- Task status bubble sounds do not have a separate global sound toggle. Each sound dropdown includes an off option; the bubble-enabled toggle controls only whether bubbles appear.
- Task status bubble sound choices are intentionally small: off, Glass, Ping, Pop, Tink, Hero, and Submarine. Defaults are Glass for completion and Ping for permission-stuck.
- Task status bubbles use a capsule-like shape with large continuous rounding. Text is two points smaller than the previous completion bubble, and the bubble height adapts to the smaller text instead of keeping the old fixed height.
- Clicking a task status bubble dismisses the bubble and its particle effect together.
- Task status bubble background color is fixed light gray-white and should not follow the system light/dark appearance. Text uses fixed dark gray tones for contrast.
- The floating signal feature should be removed completely from user-visible UI and runtime behavior. The app should not create the floating window, run its subscriptions, expose floating-signal menu items, or expose floating-signal settings. Old persisted preferences may be left unused for upgrade safety.
- Floating signal removal should be source-level removal, not only hidden UI. Floating-signal controllers, preferences, menu actions, sound players, and runtime subscriptions should not be compiled into the app unless another retained feature genuinely depends on a small shared type.
- The status menu popover opened from the menu bar is the single runtime-status surface. The Settings window should not keep a separate Activity/运行 tab because it duplicates the menu bar popover and may drift behind the current session-row logic.
