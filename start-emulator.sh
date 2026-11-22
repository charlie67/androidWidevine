#!/usr/bin/env bash
# Start the emulator, wait for it to boot, switch adbd to root and
# (optionally) launch frida-server as root.
#
# Usage: ./start-emulator.sh [--no-frida] [AVD_NAME]
#   AVD_NAME defaults to "rooted" (or $AVD).
set -euo pipefail

AVD="${AVD:-rooted}"
START_FRIDA=1
BOOT_TIMEOUT=180
FRIDA_PATH=/data/local/tmp/frida-server
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/emulator.log"
KALTURA_APK="$SCRIPT_DIR/kaltura-device-info-release.apk"
KALTURA_PKG=com.kaltura.kalturadeviceinfo

for arg in "$@"; do
  case "$arg" in
    --no-frida) START_FRIDA=0 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) AVD="$arg" ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v emulator >/dev/null || die "'emulator' not on PATH"
command -v adb >/dev/null || die "'adb' not on PATH"

wait_for_boot() {
  adb -e wait-for-device
  local waited=0
  until [[ "$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    (( waited >= BOOT_TIMEOUT )) && die "emulator did not finish booting within ${BOOT_TIMEOUT}s"
    sleep 2; (( waited += 2 ))
  done
}

ensure_root() {
  adb -e root >/dev/null
  adb -e wait-for-device
  local who
  who="$(adb -e shell whoami | tr -d '[:space:]')"
  [[ "$who" == "root" ]] || die "adb is running as '$who', not root (is this a Google Play image?)"
  log "adb is root"
}

start_frida() {
  if ! adb -e shell "test -x $FRIDA_PATH"; then
    log "no frida-server at $FRIDA_PATH, skipping"
    return
  fi
  # Kill by PID rather than 'pkill -f', which matches the shell running the command.
  local pids
  pids="$(adb -e shell pidof frida-server | tr -d '\r' || true)"
  [[ -n "$pids" ]] && adb -e shell "kill $pids"
  adb -e shell "nohup $FRIDA_PATH >/dev/null 2>&1 &"
  sleep 1
  adb -e shell pidof frida-server >/dev/null || die "frida-server failed to start"
  log "frida-server running as $(adb -e shell 'ps -o USER= -p $(pidof frida-server)' | tr -d '[:space:]')"
}

install_kaltura() {
  if adb -e shell pm list packages | tr -d '\r' | grep -qx "package:$KALTURA_PKG"; then
    log "Kaltura Device Info already installed"
  elif [[ -f "$KALTURA_APK" ]]; then
    log "installing $(basename "$KALTURA_APK")"
    adb -e install -r "$KALTURA_APK" >/dev/null || die "failed to install $KALTURA_APK"
    log "Kaltura Device Info installed"
  else
    log "no APK at $KALTURA_APK, skipping install"
  fi
}

if adb devices | grep -q '^emulator-'; then
  log "emulator already running, not starting a new one"
else
  emulator -list-avds | grep -qx "$AVD" || die "no AVD named '$AVD' (have: $(emulator -list-avds | tr '\n' ' '))"
  log "starting AVD '$AVD' (log: $LOG_FILE)"
  nohup emulator -avd "$AVD" -writable-system -no-snapshot >"$LOG_FILE" 2>&1 &
fi

log "waiting for boot..."
wait_for_boot
ensure_root
install_kaltura
if (( START_FRIDA )); then start_frida; fi
log "ready"
