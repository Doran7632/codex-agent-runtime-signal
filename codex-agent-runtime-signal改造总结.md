# codex-agent-runtime-signal 总结

生成时间：2026-06-21  

## 一句话总结

这次改造把 codex-agent-runtime-signal 从“只粗略显示少量 Codex 状态”的菜单栏工具，改成了可以按真实打开的 Codex 会话逐行展示状态、来源应用和会话名称的工作监控工具，并新增了独立的任务状态气泡提醒。

## 当前最终效果

菜单里的运行情况区域现在按一行一个 Codex 会话展示：

```text
IDEA - 运行中 - (xxx帮我安装这个软件)
IDEA - 空闲 - (帮我解决肌肉拉伤问题)
VS Code - 运行中 - (会话名称4)
Xcode - 空闲 - (会话名称5)
Codex Desktop - 运行中 - (会话名称6)
桌面终端 - 运行中 - (解释斐波那契数列)
桌面终端 - 空闲 - (黄油面包的制作)
Obsidian - 空闲 - (整理 Obsidian 笔记)
OpenDesign - 运行中 - (名称1)
```

核心判断规则：

- 一行只代表一个真实 Codex session。
- 只显示当前打开的 Codex 会话，不显示历史 resume 列表里的旧会话。
- 正在思考、执行工具、执行步骤时显示 `运行中`。
- 不在思考或执行中，但窗口仍打开在 Codex 会话中时显示 `空闲`。
- 会话名称优先使用 `codex resume` 里显示的 rename 名称。
- 如果没有 rename 名称，则使用 Codex 默认会话名，也就是第一条真实用户问题。
- 如果无法解析名称，显示 `未命名会话`，不再显示 session id。

## 已覆盖的应用来源

目前已支持识别这些 Codex 来源：

- 桌面终端中的 `codex resume`
- IDEA / JetBrains 内置终端中的 Codex
- VS Code / ChatGPT 扩展里的 Codex app-server
- Xcode 相关 Codex 进程
- Codex Desktop
- Obsidian 内通过 `codex-acp` 打开的 Codex 会话
- OpenDesign 等应用里嵌入的 Codex CLI / Computer Use 场景

识别逻辑不是只看进程名，而是组合：

- `ps` 进程扫描
- 父进程链宿主应用推断
- `lsof` 打开的 Codex rollout 文件
- `~/.codex/session_index.jsonl` 的会话名
- `~/.codex/sessions/**/rollout-*.jsonl` 的元数据和第一条真实用户问题

## 关键问题与修复

### 1. 同一应用多行显示

按 session/thread 展示，同一个应用下多个会话也会逐行显示。

### 2. 来源应用显示不准确

通过父进程链和 rollout 元数据推断真实宿主应用，例如：

- IDEA 内终端显示 `IDEA`
- VS Code 扩展显示 `VS Code`
- Obsidian 插件显示 `Obsidian`
- OpenDesign 内嵌 Codex 显示 `OpenDesign`
- 真正的系统终端才显示 `桌面终端`

### 3. 会话名称显示成 session id

现在名称解析顺序是：

1. `codex resume` / `session_index.jsonl` 的 `thread_name`
2. rollout 日志里第一条真实用户问题
3. `未命名会话`

### 4. 历史会话太多，干扰判断

曾经尝试过全量读取 `codex resume` 历史索引，但会把几十个未打开的旧会话也显示出来。

现在历史索引只作为“取名字”的数据源，不直接进入菜单展示。菜单只显示当前打开的 Codex 会话。

### 5. 空闲会话闪烁

桌面终端和部分宿主应用的空闲会话依赖 `lsof` 扫描打开的 rollout 文件。单次扫描漏报时，旧逻辑会让这条会话忽隐忽现。

现在对已经确认过的真实 `CodexSessionOpen` 做短时保活，避免单次扫描波动造成 UI 闪烁。

### 6. 同状态会话排序跳动

多个 IDEA 空闲会话状态相同、更新时间相同时，旧排序会受字典顺序和扫描顺序影响，位置总是变化。

现在增加了稳定排序兜底，按 thread identity / session id 等稳定字段排序。

### 7. 桌面终端会话被隐藏

最后一次修复的核心问题是：一个运行中的 `codex-cli` 会话会按 `codex:terminal` 来源压住其他桌面终端打开会话。

现在真实 `CodexSessionOpen` 不再按来源应用提前过滤，而是进入后续 thread 级合并。因此一个终端会话运行中时，其他打开但空闲的终端会话仍会显示。

### 8. 任务状态气泡误触发与显示问题

后续新增的任务气泡经历了几轮修正：

- 只有真正完成才弹完成气泡，中断、取消、失败、错误、权限拒绝不算完成。
- 权限卡住单独弹权限气泡，不再伪装成完成。
- 旧的历史完成事件不会在会话重新运行后重复弹出。
- 单个气泡首次出现时不再偏到刘海右侧；窗口显示前后都使用固定尺寸重新布局。
- 气泡边缘黑线已移除，原因是阴影和描边在透明固定窗口边界被裁切。

## 新增任务状态气泡提醒

新增了一个和原有声音、原有悬浮提示完全隔离的新功能：任务状态气泡。

行为规则：

- 任意一个会话真正完成时弹出完成气泡。
- 任意一个会话卡在权限确认时弹出权限气泡。
- 完成气泡使用蓝色粒子，声音为 macOS 系统声音 `Glass`。
- 权限气泡使用红色粒子，声音为 macOS 系统声音 `Ping`。
- 气泡显示在刘海正下方；无刘海或无法检测时 fallback 到主屏顶部居中、菜单栏下方。
- 多个气泡同时出现时，自上而下堆叠显示。
- 气泡显示 4 秒后自动消失。
- 点击气泡只关闭该气泡，不打开菜单、不切换应用、不跳转会话。
- 同一次完成或权限卡住只提示一次；同一会话重新运行后，才允许再次提示。

视觉规则：

- 气泡固定为 `246 x 64 pt`，不会被长文本撑大。
- 背景为固定深灰渐变，约 `#33383F` 到 `#1A1C21`，不跟随系统明暗变化。
- 文本为浅色，适配深灰底色。
- 来源应用和会话名称为单行横向滚动，内容过长时在气泡内部滚动显示。
- 蓝色和红色粒子在气泡出现时先喷散，然后轻微动态保留到气泡结束。
- 为避免黑边，当前气泡不使用窗口阴影、SwiftUI 外阴影或外描边。

设置里新增了独立配置：

- 任务气泡提醒：默认开启
- 完成提示音：`关闭`、`Glass`、`Ping`、`Pop`、`Tink`、`Hero`、`Submarine`，默认 `Glass`
- 权限提示音：`关闭`、`Glass`、`Ping`、`Pop`、`Tink`、`Hero`、`Submarine`，默认 `Ping`
- 完成/权限声音分别提供试听按钮，互不影响

## 小而美瘦身

本次继续按“只保留任务栏单击出现的界面”的方向瘦身：

- 已彻底删除旧悬浮信号灯运行链路，不再创建悬浮窗、不再订阅悬浮灯状态、不再暴露悬浮灯菜单项。
- 已删除悬浮灯专属偏好类型、控制器源码和旧 `completion-*` / `waiting-*` / `alert-*` 音效资源。
- 设置窗口已删除“运行”tab，默认进入“通用”；实时运行情况只保留在菜单栏单击弹出的面板里。
- 设置窗口不再提供“显示悬浮信号灯”“悬浮灯大小”“悬浮灯声音”等入口。
- 任务气泡声音与旧声音系统完全分离，使用两个轻量下拉偏好控制。

## 主要代码位置

会话发现：

- `Sources/CodexAgentRuntimeSignal/Services/CodexPlatformPresenceMonitor.swift`

菜单状态聚合、过滤、保活、合并：

- `Sources/CodexAgentRuntimeSignal/Stores/MenuBarStatusModel.swift`

展示文案、来源应用、排序和可见性规则：

- `Sources/CodexAgentRuntimeSignal/Support/ActivityPresentation.swift`

Codex 会话名和 rollout 元数据解析：

- `Sources/CodexAgentRuntimeSignal/Support/CodexThreadNameIndex.swift`

任务状态气泡：

- `Sources/CodexAgentRuntimeSignal/Services/CompletionBubbleController.swift`

菜单 UI：

- `Sources/CodexAgentRuntimeSignal/Views/MenuBarPanelView.swift`

设置和状态栏控制：

- `Sources/CodexAgentRuntimeSignal/Services/StatusBarController.swift`

回归测试：

- `Tests/CodexAgentRuntimeSignalCoreTests/CodexAgentRuntimeSignalCoreTests.swift`

## 最新安装包

最新打包时间：2026-06-21 18:45

产物：

- `dist/CodexAgentRuntimeSignal.dmg`
- `dist/CodexAgentRuntimeSignal.zip`
- `dist/CodexAgentRuntimeSignal-SHA256SUMS.txt`

SHA256：

```text
4738b812d1d5d718c7ba5e5c9437dd19c08d39831f59ea9dedd23336b5da5fb4  dist/CodexAgentRuntimeSignal.zip
278c273fa00010250c2d38ce66ee039b33dfc5f5f5d42709a47a55b182d5f860  dist/CodexAgentRuntimeSignal.dmg
```

验证结果：

- `swift build` 通过
- `hdiutil verify dist/CodexAgentRuntimeSignal.dmg` 通过
- `./script/verify_release_install.sh --dmg dist/CodexAgentRuntimeSignal.dmg` 通过
- `./script/verify_release_zip.sh --zip dist/CodexAgentRuntimeSignal.zip` 通过
- `codesign --verify --deep --strict --verbose=2 dist/CodexAgentRuntimeSignal.app` 通过

已知情况：

- `swift test` 在当前环境仍无法运行，原因是测试 target 编译时报 `no such module 'XCTest'`。
- `./script/package_release.sh` 会在后续 appcast/manifest 阶段返回 `exit 1`，但 DMG/ZIP 已生成，并且独立验证均通过。
- 当前构建是 ad-hoc 签名，未做 Apple notarization；首次打开时 macOS 可能需要在隐私与安全里允许。

## 当前能力边界

这版已经能覆盖大多数真实使用场景，但仍不是“魔法级 100% 检测任意软件内部的 Codex”。

可靠识别依赖至少有一种证据可见：

- 能看到 Codex 相关进程
- 能追溯父进程链
- 能通过 `lsof` 看到打开的 rollout 文件
- 能在 Codex session 日志里找到 thread id 或宿主元数据

如果某个宿主应用完全隐藏内部实现，不暴露 Codex 子进程、命令行、窗口标题、rollout 文件或可追溯父进程，macOS 用户态就无法稳定证明它内部正在运行 Codex。

## 后续建议

优先继续观察这些点：

- 长时间运行后，打开会话列表是否仍稳定。
- IDEA / VS Code / Obsidian / OpenDesign 多会话同时打开时，排序是否固定。
- 任务状态气泡是否只在真正完成或权限卡住时出现。
- 单个任务气泡是否稳定出现在刘海正下方。
- 气泡边缘是否仍有黑线或裁切痕迹。
- 桌面终端空闲会话是否既不误报，也不漏报。

如果后续继续增强，可以考虑：

- 增加 Debug 页面中的“当前 discovery 明细”，显示每条会话来自哪个 PID、哪个 rollout 文件。
- 对未知宿主应用增加更通用的 host app 映射策略。
- 给任务状态气泡增加短期通知历史，但默认不进入主菜单，避免干扰实时判断。
