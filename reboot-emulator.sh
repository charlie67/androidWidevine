#!/usr/bin/env bash
# Reboot the running emulator, then restore root and frida-server
# (both are lost on reboot).
#
# Usage: ./reboot-emulator.sh [--no-frida]
set -euo pipefail

START_FRIDA=1
BOOT_TIMEOUT=180
FRIDA_PATH=/data/local/tmp/frida-server

for arg in "$@"; do
  case "$arg" in
    --no-frida) START_FRIDA=0 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

adb devices | grep -q '^emulator-.*device$' || die "no running emulator found"

log "rebooting..."
adb -e reboot 2>/dev/null || true   # often reports "error: closed" even on success

# Wait for the device to actually go down, so we don't see the old boot_completed=1.
waited=0
while [[ "$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  (( waited >= 30 )) && die "emulator did not go down after reboot"
  sleep 1; (( waited += 1 ))
done

log "waiting for boot..."
adb -e wait-for-device
waited=0
until [[ "$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  (( waited >= BOOT_TIMEOUT )) && die "emulator did not finish booting within ${BOOT_TIMEOUT}s"
  sleep 2; (( waited += 2 ))
done

adb -e root >/dev/null
adb -e wait-for-device
who="$(adb -e shell whoami | tr -d '[:space:]')"
[[ "$who" == "root" ]] || die "adb is running as '$who', not root"
log "adb is root"

if (( START_FRIDA )); then
  if adb -e shell "test -x $FRIDA_PATH"; then
    adb -e shell "nohup $FRIDA_PATH >/dev/null 2>&1 &"
    sleep 1
    adb -e shell pidof frida-server >/dev/null || die "frida-server failed to start"
    log "frida-server running as $(adb -e shell 'ps -o USER= -p $(pidof frida-server)' | tr -d '[:space:]')"
  else
    log "no frida-server at $FRIDA_PATH, skipping"
  fi
fi

log "ready"
