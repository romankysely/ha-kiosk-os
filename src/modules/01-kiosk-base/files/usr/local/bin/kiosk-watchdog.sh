#!/usr/bin/env bash
# HA KioskOS — Chromium watchdog
# Každých 15 sekund zkontroluje zda běží Chromium, jinak ho restartuje

LOG="/var/log/kiosk-watchdog.log"
SLEEP_INTERVAL=15

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG}"
}

log "Watchdog spuštěn (PID $$)"

while true; do
    if ! pgrep -x "chromium-browse" > /dev/null 2>&1 && \
       ! pgrep -x "chromium-browser" > /dev/null 2>&1; then
        log "Chromium neběží — restartuji..."
        DISPLAY=:0 /usr/local/bin/chromium-kiosk &
        log "Chromium spuštěn (PID $!)"
    fi
    sleep "${SLEEP_INTERVAL}"
done
