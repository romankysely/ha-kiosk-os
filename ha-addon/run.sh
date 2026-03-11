#!/usr/bin/env bash
# HA KioskOS — Addon startup skript
set -euo pipefail

DATA_DIR="/data"
mkdir -p "${DATA_DIR}/kiosks"

# Vygeneruj SSH klíč páru pokud neexistuje
SSH_KEY_FILE="${DATA_DIR}/kiosk_builder_rsa"
if [ ! -f "${SSH_KEY_FILE}" ]; then
    echo "[addon] Generuji SSH klíč pár..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_FILE}" -N "" \
        -C "ha-kiosk-os-builder@$(date +%Y%m%d)" \
        -q
    echo "[addon] SSH klíč vygenerován: ${SSH_KEY_FILE}"
fi

echo "[addon] Spouštím Kiosk Builder web server na portu 8099..."
exec python3 /app/main.py
