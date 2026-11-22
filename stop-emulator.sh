#!/usr/bin/env bash
# Shut down the running emulator and clean up after it:
#   - stops frida-server on the device
#   - asks the emulator to quit, force-killing it if it hangs
#   - removes stale AVD lock files (these cause "another emulator instance
#     is running" errors after a crash)
#   - removes the emulator.log written by start-emulator.sh
#
# Usage: ./stop-emulator.sh [--keep-log]
set -euo pipefail

KEEP_LOG=0
SHUTDOWN_TIMEOUT=30
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/emulator.log"
AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"

for arg in "$@"; do
  case "$arg" in
    --keep-log) KEEP_LOG=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

emulator_pids() { pgrep -f 'qemu-system-.*-avd' || true; }

if adb devices | grep -q '^emulator-.*device$'; then
  pids="$(adb -e shell pidof frida-server 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$pids" ]]; then
    adb -e shell "kill $pids" 2>/dev/null || true
    log "stopped frida-server"
  fi

  log "shutting down emulator..."
  adb -e emu kill >/dev/null 2>&1 || true
else
  log "no emulator connected to adb"
fi

# Wait for the emulator process(es) to exit, then force-kill anything left.
waited=0
while [[ -n "$(emulator_pids)" ]] && (( waited < SHUTDOWN_TIMEOUT )); do
  sleep 1; (( waited += 1 ))
done
if [[ -n "$(emulator_pids)" ]]; then
  log "emulator still running after ${SHUTDOWN_TIMEOUT}s, force-killing"
  pkill -9 -f 'qemu-system-.*-avd' || true
  sleep 1
fi
[[ -z "$(emulator_pids)" ]] && log "emulator stopped"

# Lock files are only stale if no emulator is running.
if [[ -z "$(emulator_pids)" ]]; then
  locks="$(find "$AVD_HOME" -maxdepth 2 -name '*.lock' 2>/dev/null || true)"
  if [[ -n "$locks" ]]; then
    echo "$locks" | while read -r lock; do rm -rf "$lock"; done
    log "removed $(echo "$locks" | wc -l | tr -d ' ') stale lock file(s)"
  fi
fi

# Drop the offline "emulator-5554" entry adb can keep around.
adb reconnect offline >/dev/null 2>&1 || true

if (( ! KEEP_LOG )) && [[ -f "$LOG_FILE" ]]; then
  rm -f "$LOG_FILE"
  log "removed $(basename "$LOG_FILE")"
fi

log "done"
