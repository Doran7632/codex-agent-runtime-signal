#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
STATE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-agent-runtime-signal-local-integrations.XXXXXX")"
STATE_FILE="$STATE_ROOT/status.json"
OUTPUT_FILE="$STATE_ROOT/output.json"

cleanup() {
  rm -rf "$STATE_ROOT"
}
trap cleanup EXIT

pass() {
  printf "[ok] %s\n" "$1"
}

die() {
  printf "[fail] %s\n" "$1" >&2
  exit 1
}

swift_tool() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    swift "$@"
  elif [[ -d "$XCODE_DEVELOPER_DIR" ]]; then
    DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" swift "$@"
  else
    swift "$@"
  fi
}

expect_json() {
  local description="$1"
  local expression="$2"
  /usr/bin/python3 - "$OUTPUT_FILE" "$expression" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
expression = sys.argv[2]
sessions = data.get("sessions", [])
session_map = {item.get("session_id"): item for item in sessions}
namespace = {
    "data": data,
    "sessions": session_map,
}
if not eval(expression, {"__builtins__": {}}, namespace):
    raise SystemExit(f"expectation failed: {expression}\n{json.dumps(data, indent=2, ensure_ascii=False)}")
PY
  pass "$description"
}

cd "$ROOT_DIR"

swift_tool build --product codex-agent-runtime-signal >/dev/null
export CODEX_AGENT_RUNTIME_SIGNAL_BIN="$(swift_tool build --product codex-agent-runtime-signal --show-bin-path)/codex-agent-runtime-signal"

GENERIC_STATE="$STATE_ROOT/generic-status.json"
printf '{"event":"AgentStarted","agent":"local-script","session_id":"local-script-hook"}' \
  | CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$GENERIC_STATE" ./scripts/generic-codex-agent-runtime-signal-hook
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$GENERIC_STATE" ./scripts/codex-agent-runtime-signal status --json >"$OUTPUT_FILE"
expect_json "generic agent hook maps local-script start event" \
  'data["aggregate"] == "working" and data["display_state"] == "active" and sessions["local-script-hook"]["agent"] == "local-script" and sessions["local-script-hook"]["last_event"] == "AgentStarted"'

GENERIC_PERMISSION_STATE="$STATE_ROOT/generic-permission-status.json"
printf '{"event":"ApprovalRequired","source":"local-agent","task_id":"approve-1"}' \
  | CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$GENERIC_PERMISSION_STATE" ./scripts/generic-codex-agent-runtime-signal-hook
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$GENERIC_PERMISSION_STATE" ./scripts/codex-agent-runtime-signal status --json >"$OUTPUT_FILE"
expect_json "generic agent hook maps approval event to permission" \
  'data["aggregate"] == "permission" and data["display_state"] == "permission" and sessions["approve-1"]["agent"] == "local-agent" and sessions["approve-1"]["signal"] == "permission_request"'

CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$STATE_FILE" ./scripts/codex-agent-runtime-signal working \
  --session local-script-main \
  --agent local-script \
  --event AgentStarted \
  --json >"$OUTPUT_FILE"
expect_json "local script working signal writes active session" \
  'data["aggregate"] == "working" and data["display_state"] == "active" and sessions["local-script-main"]["agent"] == "local-script" and sessions["local-script-main"]["last_event"] == "AgentStarted"'

CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$STATE_FILE" ./scripts/codex-agent-runtime-signal attention \
  --session local-script-main \
  --agent local-script \
  --event NeedsReview \
  --json >"$OUTPUT_FILE"
expect_json "local script attention signal writes review state" \
  'data["aggregate"] == "attention" and data["display_state"] == "needs_review" and sessions["local-script-main"]["last_event"] == "NeedsReview"'

CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$STATE_FILE" ./scripts/codex-agent-runtime-signal done \
  --session local-script-main \
  --agent local-script \
  --event AgentFinished \
  --json >"$OUTPUT_FILE"
expect_json "local script done does not hide unresolved attention" \
  'data["aggregate"] == "attention" and data["display_state"] == "needs_review" and data["recent_events"][0]["signal"] == "done" and sessions["local-script-main"]["signal"] == "attention"'

DONE_STATE="$STATE_ROOT/done-status.json"
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$DONE_STATE" ./scripts/codex-agent-runtime-signal working \
  --session local-script-finish \
  --agent local-script \
  --event AgentStarted >/dev/null
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$DONE_STATE" ./scripts/codex-agent-runtime-signal done \
  --session local-script-finish \
  --agent local-script \
  --event AgentFinished \
  --json >"$OUTPUT_FILE"
expect_json "local script done signal writes completed state without pending review" \
  'data["aggregate"] == "done" and data["display_state"] == "completed" and sessions["local-script-finish"]["last_event"] == "AgentFinished"'

RUN_STATE="$STATE_ROOT/run-status.json"
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$RUN_STATE" ./scripts/codex-agent-runtime-signal-run \
  --session local-script-run-ok \
  --agent local-script \
  --start-event AgentStarted \
  --done-event AgentFinished \
  --blocked-event AgentFailed \
  -- /bin/sh -c "exit 0" >/dev/null
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$RUN_STATE" ./scripts/codex-agent-runtime-signal status --json >"$OUTPUT_FILE"
expect_json "codex-agent-runtime-signal-run marks successful local script command done" \
  'data["aggregate"] == "done" and sessions["local-script-run-ok"]["signal"] == "done" and sessions["local-script-run-ok"]["last_event"] == "AgentFinished"'

FAIL_STATE="$STATE_ROOT/run-failure-status.json"
set +e
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$FAIL_STATE" ./scripts/codex-agent-runtime-signal-run \
  --session local-script-run-fail \
  --agent local-script \
  --start-event AgentStarted \
  --done-event AgentFinished \
  --blocked-event AgentFailed \
  -- /bin/sh -c "exit 6" >/dev/null
run_status=$?
set -e
[[ "$run_status" -eq 6 ]] || die "codex-agent-runtime-signal-run did not preserve failed local script command exit code"
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$FAIL_STATE" ./scripts/codex-agent-runtime-signal status --json >"$OUTPUT_FILE"
expect_json "codex-agent-runtime-signal-run marks failed local script command blocked" \
  'data["aggregate"] == "blocked" and sessions["local-script-run-fail"]["signal"] == "blocked" and sessions["local-script-run-fail"]["last_event"] == "AgentFailed:6"'

PRIORITY_STATE="$STATE_ROOT/priority-status.json"
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$PRIORITY_STATE" ./scripts/codex-agent-runtime-signal blocked \
  --session local-script-alert \
  --agent local-script \
  --event AgentFailed >/dev/null
CODEX_AGENT_RUNTIME_SIGNAL_STATE_FILE="$PRIORITY_STATE" ./scripts/codex-agent-runtime-signal working \
  --session local-script \
  --agent script \
  --event ScriptStarted \
  --json >"$OUTPUT_FILE"
expect_json "local script working does not override blocked alert" \
  'data["aggregate"] == "blocked" and sessions["local-script-alert"]["signal"] == "blocked" and sessions["local-script"]["signal"] == "working"'

echo "local integration verifier: ok"
