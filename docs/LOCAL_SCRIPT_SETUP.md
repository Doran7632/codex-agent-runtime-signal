# Local Script Setup

Any local tool can update codex-agent-runtime-signal by calling the CLI wrapper from the project root. The wrapper prefers the installed release binary at `dist/bin/codex-agent-runtime-signal` and falls back to the debug build when present.

Prefer passing a stable `--session` for real jobs so the menu can explain which process is active. Bare commands such as `./scripts/codex-agent-runtime-signal working` are treated as a `manual` session and still respect aggregation priority, so a red permission or blocked session will not be overwritten by a manual working signal. `idle` and `reset` are the manual clear path.

The CLI is intentionally strict about options. A typo such as `--sesion` or a missing value after `--session` exits with an error instead of silently creating a `manual` session.

## Generic Script

If a local runner can emit JSON, use the generic hook. It recognizes common
fields such as `event`, `status`, `signal`, `agent`, `source`, `session_id`,
`task_id`, and `run_id`:

```bash
echo '{"event":"AgentStarted","agent":"local-runner","session_id":"job-1"}' \
  | ./scripts/generic-codex-agent-runtime-signal-hook

echo '{"status":"failed","source":"local-runner","task_id":"job-1"}' \
  | ./scripts/generic-codex-agent-runtime-signal-hook
```

```bash
./scripts/codex-agent-runtime-signal working \
  --session nightly-build \
  --agent script \
  --event BuildStarted

./scripts/codex-agent-runtime-signal done \
  --session nightly-build \
  --agent script \
  --event BuildFinished
```

Use `blocked` for failures:

```bash
./scripts/codex-agent-runtime-signal blocked \
  --session nightly-build \
  --agent script \
  --event BuildFailed
```

If a script runs from another directory, resolve this project path first and quote it:

```bash
CODEX_AGENT_RUNTIME_SIGNAL_ROOT="/path/to/CodexAgentRuntimeSignal"
"$CODEX_AGENT_RUNTIME_SIGNAL_ROOT/scripts/codex-agent-runtime-signal" working --session job --agent script --event Started
```

## Wrap Any Command

For simple jobs, let `codex-agent-runtime-signal-run` set the light for you:

```bash
./scripts/codex-agent-runtime-signal-run \
  --session nightly-build \
  --agent script \
  -- ./run-build.sh
```

It writes `working` before the command starts, `done` when the command exits `0`, and `blocked` when the command exits non-zero. The wrapped command's original exit code is preserved, so CI or shell scripts can still fail normally.

## Explicit Phase Commands

If a local workflow can run shell commands before and after agent work, map it
like this:

```bash
./scripts/codex-agent-runtime-signal working \
  --session local-script-main \
  --agent local-script \
  --event AgentStarted

./scripts/codex-agent-runtime-signal attention \
  --session local-script-main \
  --agent local-script \
  --event NeedsReview

./scripts/codex-agent-runtime-signal done \
  --session local-script-main \
  --agent local-script \
  --event AgentFinished
```

`done` is a green completed state and automatically returns to idle after the completed TTL.

If the workflow can run one command around a job, use the wrapper instead:

```bash
./scripts/codex-agent-runtime-signal-run \
  --session local-script-main \
  --agent local-script \
  --start-event AgentStarted \
  --done-event AgentFinished \
  --blocked-event AgentFailed \
  -- ./local-agent-command
```

## Machine-Readable Status

Use `--json` when another script needs to branch on the aggregate state:

```bash
status_json="$(./scripts/codex-agent-runtime-signal status --json)"
display_state="$(printf '%s' "$status_json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["display_state"])')"

if [ "$display_state" = "blocked" ] || [ "$display_state" = "permission" ]; then
  echo "Agent needs attention"
fi
```

State-changing commands can also return JSON:

```bash
./scripts/codex-agent-runtime-signal working \
  --session nightly-build \
  --agent script \
  --event BuildStarted \
  --json
```
