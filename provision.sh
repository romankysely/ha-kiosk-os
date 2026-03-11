#!/usr/bin/env bash
# =============================================================================
# HA KioskOS — Provisioning skript
# Spusť na čerstvém stock RPi OS Lite 64-bit jako root
#
# Použití:
#   sudo bash provision.sh
#   nebo vzdáleně:
#   curl -fsSL https://raw.githubusercontent.com/romankysely/ha-kiosk-os/dev/provision.sh | sudo bash
#
# Před spuštěním zkopíruj kiosk.conf na boot partition:
#   /boot/firmware/kiosk.conf
# =============================================================================
set -euo pipefail

# ─── Konfigurace ─────────────────────────────────────────────────────────────
REPO_URL="https://github.com/romankysely/ha-kiosk-os.git"
REPO_BRANCH="dev"
REPO_DIR="/opt/ha-kiosk-os"
KIOSK_CONF="/boot/firmware/kiosk.conf"
LOG="/var/log/kiosk-provision.log"
DONE_FLAG="/etc/ha-kiosk-os_provisioned"

DEFAULT_MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring"

# ─── Barvy ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ─── Logování ────────────────────────────────────────────────────────────────
log()     { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
info()    { log "${BLUE}[INFO]${NC} $*"; }
ok()      { log "${GREEN}[OK]${NC}   $*"; }
warn()    { log "${YELLOW}[WARN]${NC} $*"; }
error()   { log "${RED}[ERR]${NC}  $*"; exit 1; }
section() { log ""; log "══════════════════════════════════════"; log "  $*"; log "══════════════════════════════════════"; }

# ─── Root check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Skript musí běžet jako root: sudo bash $0"
    exit 1
fi

mkdir -p "$(dirname "$LOG")"
touch "$LOG"

section "HA KioskOS — Provisioning"
info "Log: $LOG"
info "Datum: $(date)"

# ─── Idempotence check ───────────────────────────────────────────────────────
if [[ -f "$DONE_FLAG" ]]; then
    warn "Provisioning již byl proveden ($(cat "$DONE_FLAG")). Přeskakuji."
    warn "Smaž $DONE_FLAG pro opakované spuštění."
    exit 0
fi

# ─── 1. Čekání na síť ────────────────────────────────────────────────────────
section "Čekám na síťové připojení..."
ATTEMPTS=0
MAX_ATTEMPTS=30
until ping -c1 -W2 8.8.8.8 &>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge $MAX_ATTEMPTS ]]; then
        error "Síť není dostupná po ${MAX_ATTEMPTS} pokusech. Zkontroluj připojení."
    fi
    info "Pokus $ATTEMPTS/$MAX_ATTEMPTS — čekám 2s..."
    sleep 2
done
ok "Síť dostupná"

# ─── 2. Aktualizace balíčků ──────────────────────────────────────────────────
section "Aktualizuji seznam balíčků..."
apt-get update -qq
ok "apt-get update hotovo"

# ─── 3. Nainstaluj git (pokud chybí) ─────────────────────────────────────────
if ! command -v git &>/dev/null; then
    info "Instaluji git..."
    apt-get install -y -qq git
fi

# ─── 4. Klonování repozitáře ─────────────────────────────────────────────────
section "Klonovanie repozitáře..."
if [[ -d "$REPO_DIR/.git" ]]; then
    info "Repo již existuje, aktualizuji..."
    git -C "$REPO_DIR" fetch origin
    git -C "$REPO_DIR" checkout "$REPO_BRANCH"
    git -C "$REPO_DIR" pull origin "$REPO_BRANCH"
else
    info "Klonovanie $REPO_URL (větev $REPO_BRANCH)..."
    git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$REPO_DIR"
fi
ok "Repozitář připraven v $REPO_DIR"

# ─── 5. Načtení konfigurace ───────────────────────────────────────────────────
section "Načítám konfiguraci..."
if [[ -f "$KIOSK_CONF" ]]; then
    info "Načítám $KIOSK_CONF..."
    # shellcheck source=/dev/null
    source "$KIOSK_CONF"
    ok "kiosk.conf načten"
    info "Hostname:    ${KIOSK_HOSTNAME:-NEDEFINO}"
    info "HA URL:      ${KIOSK_HA_URL:-NEDEFINO}"
    info "Dashboard:   ${KIOSK_DASHBOARD_URL:-NEDEFINO}"
else
    warn "kiosk.conf nenalezen — použiji výchozí moduly a kiosk se nakonfiguruje manuálně"
fi

MODULES="${KIOSK_MODULES:-$DEFAULT_MODULES}"
info "Moduly k instalaci: $MODULES"

# ─── 6. Instalace modulů ──────────────────────────────────────────────────────
section "Instaluji moduly..."
for MODULE in $MODULES; do
    MODULE_DIR="$REPO_DIR/src/modules/$MODULE"

    if [[ ! -d "$MODULE_DIR" ]]; then
        warn "Modul $MODULE nenalezen v $MODULE_DIR — přeskakuji"
        continue
    fi

    log ""
    info "--- Modul: $MODULE ---"

    # Kopírování files/ do rootfs
    if [[ -d "$MODULE_DIR/files" ]]; then
        info "Kopíruji files/ do /"
        cp -r "$MODULE_DIR/files/." /
        ok "files/ zkopírovány"
    fi

    # Spuštění install skriptu
    INSTALL_SCRIPT="$MODULE_DIR/start_chroot_script"
    if [[ -f "$INSTALL_SCRIPT" ]]; then
        info "Spouštím $INSTALL_SCRIPT..."
        chmod +x "$INSTALL_SCRIPT"
        bash "$INSTALL_SCRIPT" 2>&1 | tee -a "$LOG"
        ok "Modul $MODULE nainstalován"
    else
        warn "start_chroot_script nenalezen v $MODULE_DIR"
    fi
done

# ─── 7. Firstboot konfigurace ─────────────────────────────────────────────────
section "Konfigurace kiosku (firstboot)..."
FIRSTBOOT_SCRIPT="/usr/local/bin/firstboot.sh"

if [[ -f "$KIOSK_CONF" && -f "$FIRSTBOOT_SCRIPT" ]]; then
    info "Spouštím firstboot.sh pro per-device konfiguraci..."
    chmod +x "$FIRSTBOOT_SCRIPT"
    bash "$FIRSTBOOT_SCRIPT" 2>&1 | tee -a "$LOG"
    # firstboot.sh sám provede reboot na konci
    # Sem se dostaneme jen pokud firstboot.sh neskončí rebooten
elif [[ ! -f "$KIOSK_CONF" ]]; then
    warn "kiosk.conf chybí — přeskakuji per-device konfiguraci"
    warn "Zkopíruj kiosk.conf na /boot/firmware/ a spusť firstboot.sh ručně:"
    warn "  sudo bash $FIRSTBOOT_SCRIPT"
elif [[ ! -f "$FIRSTBOOT_SCRIPT" ]]; then
    warn "firstboot.sh nenalezen — modul 05-ha-bootstrap nebyl nainstalován?"
fi

# ─── 8. Dokončení ─────────────────────────────────────────────────────────────
echo "Provisioning dokončen: $(date)" > "$DONE_FLAG"

section "Provisioning HOTOVÝ!"
ok "Log uložen v: $LOG"
ok "Flag: $DONE_FLAG"

if [[ ! -f "$KIOSK_CONF" ]]; then
    warn ""
    warn "DŮLEŽITÉ: Kiosk ještě není nakonfigurován."
    warn "1. Zkopíruj kiosk.conf na /boot/firmware/kiosk.conf"
    warn "2. Spusť: sudo bash /usr/local/bin/firstboot.sh"
else
    info "Rebootuji za 5 sekund..."
    sleep 5
    reboot
fi
