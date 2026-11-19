#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$ROOT_DIR/dist/bin"
INSTALL_PATH="$INSTALL_DIR/codex-agent-runtime-signal"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

cd "$ROOT_DIR"

swift_tool() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    swift "$@"
  elif [[ -d "$XCODE_DEVELOPER_DIR" ]]; then
    DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" swift "$@"
  else
    swift "$@"
  fi
}

swift_tool build -c release --product codex-agent-runtime-signal
mkdir -p "$INSTALL_DIR"
cp "$(swift_tool build -c release --show-bin-path)/codex-agent-runtime-signal" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo "Installed codex-agent-runtime-signal: $INSTALL_PATH"
