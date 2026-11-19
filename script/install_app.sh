#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexAgentRuntimeSignal"
BUNDLE_ID="com.codexagentruntimesignal.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${CODEX_AGENT_RUNTIME_SIGNAL_APP_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="$LAUNCH_AGENT_DIR/$BUNDLE_ID.plist"
ENABLE_LOGIN_ITEM=0
OPEN_AFTER_INSTALL=1
REBUILD_APP=0
SOURCE_APP=""
SOURCE_DMG=""
TMP_ROOT=""
MOUNT_DIR=""

usage() {
  cat <<EOF
usage: $0 [--login-item] [--no-open] [--rebuild] [--source-app <path>] [--dmg <path>]

Install codex-agent-runtime-signal into the current user's Applications directory.

By default the script installs an existing dist/$APP_NAME.app when present,
so release zip users do not need Xcode or Swift installed. Use --rebuild to
force a fresh release build from source, or --dmg to install from a DMG.
EOF
}

absolute_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf "%s\n" "$path"
  else
    printf "%s/%s\n" "$(pwd)" "$path"
  fi
}

cleanup() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

write_launch_agent_plist() {
  /usr/bin/python3 - "$LAUNCH_AGENT_PLIST" "$BUNDLE_ID" "$INSTALLED_APP" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
bundle_id = sys.argv[2]
installed_app = sys.argv[3]

plist = {
    "Label": bundle_id,
    "ProgramArguments": [
        "/usr/bin/open",
        installed_app,
    ],
    "RunAtLoad": True,
    "StandardOutPath": "/tmp/codex-agent-runtime-signal/app.out.log",
    "StandardErrorPath": "/tmp/codex-agent-runtime-signal/app.err.log",
}

plist_path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML, sort_keys=False))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --login-item|--launch-at-login)
      ENABLE_LOGIN_ITEM=1
      shift
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=0
      shift
      ;;
    --rebuild)
      REBUILD_APP=1
      shift
      ;;
    --source-app)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        echo "install_app: missing value for --source-app" >&2
        exit 2
      fi
      SOURCE_APP="$(absolute_path "$2")"
      shift 2
      ;;
    --dmg|--from-dmg)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        echo "install_app: missing value for $1" >&2
        exit 2
      fi
      SOURCE_DMG="$(absolute_path "$2")"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ -n "$SOURCE_APP" && -n "$SOURCE_DMG" ]]; then
  echo "install_app: use either --source-app or --dmg, not both" >&2
  exit 2
fi

if [[ "$REBUILD_APP" -eq 1 ]] && { [[ -n "$SOURCE_APP" ]] || [[ -n "$SOURCE_DMG" ]]; }; then
  echo "install_app: --rebuild cannot be combined with --source-app or --dmg" >&2
  exit 2
fi

if [[ "$REBUILD_APP" -eq 1 ]]; then
  APP_BUNDLE="$("$ROOT_DIR/script/package_app.sh" --release)"
elif [[ -n "$SOURCE_APP" ]]; then
  APP_BUNDLE="$SOURCE_APP"
elif [[ -n "$SOURCE_DMG" ]]; then
  [[ -f "$SOURCE_DMG" ]] || { echo "install_app: DMG not found at $SOURCE_DMG" >&2; exit 1; }
  TMP_ROOT="$(mktemp -d)"
  MOUNT_DIR="$TMP_ROOT/mount"
  mkdir -p "$MOUNT_DIR"
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$SOURCE_DMG" >/dev/null
  APP_BUNDLE="$MOUNT_DIR/$APP_NAME.app"
elif [[ -x "$ROOT_DIR/dist/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]]; then
  APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
else
  APP_BUNDLE="$("$ROOT_DIR/script/package_app.sh" --release)"
fi

if [[ ! -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
  echo "install_app: app executable not found in $APP_BUNDLE" >&2
  exit 1
fi
SOURCE_DESCRIPTION="$APP_BUNDLE"
if [[ -z "$TMP_ROOT" ]]; then
  TMP_ROOT="$(mktemp -d)"
fi
CLEAN_APP="$TMP_ROOT/source/$APP_NAME.app"
mkdir -p "$(dirname "$CLEAN_APP")"
ditto --norsrc "$APP_BUNDLE" "$CLEAN_APP"
plutil -lint "$CLEAN_APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$CLEAN_APP" >/dev/null 2>&1

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto --norsrc "$CLEAN_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" >/dev/null 2>&1

if [[ "$ENABLE_LOGIN_ITEM" -eq 1 ]]; then
  mkdir -p "$LAUNCH_AGENT_DIR" /tmp/codex-agent-runtime-signal
  write_launch_agent_plist

  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PLIST"
fi

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  /usr/bin/open "$INSTALLED_APP"
fi

echo "Installed app: $INSTALLED_APP"
echo "Source app: $SOURCE_DESCRIPTION"
if [[ "$ENABLE_LOGIN_ITEM" -eq 1 ]]; then
  echo "Launch at login: enabled via $LAUNCH_AGENT_PLIST"
fi
