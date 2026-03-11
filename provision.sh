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
REPORT="/var/log/kiosk-provision-report.txt"
DONE_FLAG="/etc/ha-kiosk-os_provisioned"

DEFAULT_MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring"

# ─── Čas startu ──────────────────────────────────────────────────────────────
START_TIME=$(date +%s)
START_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# ─── Barvy ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─── Elapsed time ─────────────────────────────────────────────────────────────
elapsed() {
    local secs=$(( $(date +%s) - START_TIME ))
    printf "%02d:%02d" $((secs / 60)) $((secs % 60))
}

# ─── Logování ────────────────────────────────────────────────────────────────
log()     { echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
info()    { log "${BLUE}[INFO]${NC} $*"; }
ok()      { log "${GREEN}[ OK ]${NC} $*"; }
warn()    { log "${YELLOW}[WARN]${NC} $*"; }
error()   { log "${RED}[ERR!]${NC} $*"; exit 1; }

section() {
    log ""
    log "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    log "${BOLD}${CYAN}║${NC}  $*"
    log "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    log "  ⏱  Čas od startu: $(elapsed)"
}

# Sledování výsledků modulů
MODULE_RESULTS=()

# ─── Root check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Skript musí běžet jako root: sudo bash $0"
    exit 1
fi

mkdir -p "$(dirname "$LOG")"
touch "$LOG"

# ─── Úvodní banner ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}  ║        HA KioskOS  —  Automatická instalace          ║${NC}"
echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════════╝${NC}"
echo -e "${BOLD}  Datum:  $START_DATE${NC}"
echo -e "${BOLD}  Log:    $LOG${NC}"
echo ""
log "=========================================="
log "HA KioskOS Provisioning zahájen: $START_DATE"
log "=========================================="

# ─── Idempotence check ───────────────────────────────────────────────────────
if [[ -f "$DONE_FLAG" ]]; then
    warn "Provisioning již byl proveden ($(cat "$DONE_FLAG"))."
    warn "Smaž $DONE_FLAG pro opakované spuštění."
    exit 0
fi

# ─── 1. Čekání na síť ────────────────────────────────────────────────────────
section "[1/7] Čekám na síťové připojení"
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
ok "Síť dostupná ($(elapsed) od startu)"

# ─── 2. Aktualizace balíčků ──────────────────────────────────────────────────
section "[2/7] Aktualizuji seznam balíčků"
info "Spouštím apt-get update (může trvat 1-2 min)..."
apt-get update -qq
ok "apt-get update hotovo"

# ─── 3. Příprava nástrojů ────────────────────────────────────────────────────
section "[3/7] Příprava nástrojů"
if ! command -v git &>/dev/null; then
    info "Instaluji git..."
    apt-get install -y -qq git
    ok "git nainstalován"
else
    ok "git již nainstalován ($(git --version))"
fi

# ─── 4. Klonování repozitáře ─────────────────────────────────────────────────
section "[4/7] Stahuji ha-kiosk-os repozitář"
if [[ -d "$REPO_DIR/.git" ]]; then
    info "Repo již existuje, aktualizuji na větev $REPO_BRANCH..."
    git -C "$REPO_DIR" fetch origin
    git -C "$REPO_DIR" checkout "$REPO_BRANCH"
    git -C "$REPO_DIR" pull origin "$REPO_BRANCH"
else
    info "Klonovanie $REPO_URL (větev $REPO_BRANCH)..."
    git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$REPO_DIR"
fi
ok "Repozitář připraven v $REPO_DIR"

# ─── 5. Načtení konfigurace ───────────────────────────────────────────────────
section "[5/7] Načítám konfiguraci"
if [[ -f "$KIOSK_CONF" ]]; then
    info "Načítám $KIOSK_CONF..."
    # shellcheck source=/dev/null
    source "$KIOSK_CONF"
    ok "kiosk.conf načten"
    echo ""
    info "  ┌─── Konfigurace kiosku ─────────────────────────────"
    info "  │  Hostname:    ${KIOSK_HOSTNAME:-NEDEFINO}"
    info "  │  HA URL:      ${KIOSK_HA_URL:-NEDEFINO}"
    info "  │  Dashboard:   ${KIOSK_DASHBOARD_URL:-NEDEFINO}"
    info "  │  HA User:     ${KIOSK_HA_USERNAME:-NEDEFINO}"
    info "  │  Síť:         ${KIOSK_NETWORK:-dhcp}"
    info "  └────────────────────────────────────────────────────"
else
    warn "kiosk.conf nenalezen — použiji výchozí moduly"
    warn "Kiosk bude nutné nakonfigurovat manuálně po provisioning"
fi

MODULES="${KIOSK_MODULES:-$DEFAULT_MODULES}"
# Přetvoř řetězec na pole pro počítání
read -ra MODULE_ARRAY <<< "$MODULES"
MODULE_TOTAL=${#MODULE_ARRAY[@]}
info "Počet modulů k instalaci: ${MODULE_TOTAL}"
info "Moduly: $MODULES"

# ─── 6. Instalace modulů ──────────────────────────────────────────────────────
section "[6/7] Instaluji moduly (nejdelší část — typicky 15-30 min)"
info "Celkem modulů: ${MODULE_TOTAL} — nezavírej SSH okno!"
echo ""

MODULE_NUM=0
for MODULE in $MODULES; do
    MODULE_NUM=$((MODULE_NUM + 1))
    MODULE_DIR="$REPO_DIR/src/modules/$MODULE"

    echo ""
    log "${BOLD}  ┌─── Modul [${MODULE_NUM}/${MODULE_TOTAL}]: ${MODULE} ────────────────────────────${NC}"
    log "  │  Čas od startu: $(elapsed)"

    if [[ ! -d "$MODULE_DIR" ]]; then
        warn "  │  Modul $MODULE nenalezen v $MODULE_DIR — přeskakuji"
        log "  └────────────────────────────────────────────────────────"
        MODULE_RESULTS+=("⚠  [$MODULE_NUM/$MODULE_TOTAL] $MODULE — nenalezen, přeskočen")
        continue
    fi

    # Kopírování files/ do rootfs
    if [[ -d "$MODULE_DIR/files" ]]; then
        info "  │  Kopíruji files/ → /"
        cp -r "$MODULE_DIR/files/." /
        ok "  │  files/ zkopírovány"
    fi

    # Spuštění install skriptu
    INSTALL_SCRIPT="$MODULE_DIR/start_chroot_script"
    if [[ -f "$INSTALL_SCRIPT" ]]; then
        info "  │  Spouštím start_chroot_script..."
        chmod +x "$INSTALL_SCRIPT"
        bash "$INSTALL_SCRIPT" 2>&1 | tee -a "$LOG"
        ok "  │  Modul $MODULE nainstalován ✓"
        MODULE_RESULTS+=("✓  [$MODULE_NUM/$MODULE_TOTAL] $MODULE — OK")
    else
        warn "  │  start_chroot_script nenalezen — přeskakuji"
        MODULE_RESULTS+=("⚠  [$MODULE_NUM/$MODULE_TOTAL] $MODULE — bez install skriptu")
    fi
    log "  └────────────────────────────────────────────────────────"
done

ok "Všechny moduly zpracovány ($(elapsed) od startu)"

# ─── 7. Firstboot konfigurace ─────────────────────────────────────────────────
section "[7/7] Per-device konfigurace (firstboot)"
FIRSTBOOT_SCRIPT="/usr/local/bin/firstboot.sh"

if [[ -f "$KIOSK_CONF" && -f "$FIRSTBOOT_SCRIPT" ]]; then
    info "Spouštím firstboot.sh pro per-device konfiguraci..."
    chmod +x "$FIRSTBOOT_SCRIPT"
    bash "$FIRSTBOOT_SCRIPT" 2>&1 | tee -a "$LOG"
    # firstboot.sh sám provede reboot na konci
    # Sem se dostaneme jen pokud firstboot.sh neskončí rebooten
elif [[ ! -f "$KIOSK_CONF" ]]; then
    warn "kiosk.conf chybí — přeskakuji per-device konfiguraci"
    warn "Po dokončení zkopíruj kiosk.conf na /boot/firmware/kiosk.conf"
    warn "a spusť: sudo bash $FIRSTBOOT_SCRIPT"
elif [[ ! -f "$FIRSTBOOT_SCRIPT" ]]; then
    warn "firstboot.sh nenalezen — modul 05-ha-bootstrap nebyl nainstalován?"
fi

# ─── Závěrečný report ─────────────────────────────────────────────────────────
END_TIME=$(date +%s)
TOTAL_SECS=$(( END_TIME - START_TIME ))
TOTAL_MIN=$((TOTAL_SECS / 60))
TOTAL_SEC=$((TOTAL_SECS % 60))

echo "Provisioning dokončen: $(date)" > "$DONE_FLAG"

# Sestav zprávu
{
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          HA KioskOS — PROVISIONING REPORT                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Zahájeno:      $START_DATE"
echo "  Dokončeno:     $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Celková doba:  ${TOTAL_MIN} min ${TOTAL_SEC} sec"
echo ""
echo "─── Konfigurace kiosku ────────────────────────────────────────"
echo "  Hostname:    ${KIOSK_HOSTNAME:-NEBYLO NASTAVENO}"
echo "  HA URL:      ${KIOSK_HA_URL:-NEBYLO NASTAVENO}"
echo "  HA User:     ${KIOSK_HA_USERNAME:-NEBYLO NASTAVENO}"
echo "  Dashboard:   ${KIOSK_DASHBOARD_URL:-NEBYLO NASTAVENO}"
echo "  Síť:         ${KIOSK_NETWORK:-dhcp}"
echo "  Moduly:      $MODULES"
echo ""
echo "─── Výsledky instalace modulů ─────────────────────────────────"
for result in "${MODULE_RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "─── Logy ──────────────────────────────────────────────────────"
echo "  Provisioning: $LOG"
echo "  Firstboot:    /var/log/kiosk-firstboot.log (po rebootu)"
echo "  Tento report: $REPORT"
echo ""
if [[ -f "$KIOSK_CONF" ]]; then
    echo "─── Stav ──────────────────────────────────────────────────────"
    echo "  ✓ kiosk.conf načten — RPi se za chvíli restartuje"
    echo "  ✓ Po rebootu: Chromium → HA dashboard"
else
    echo "─── POZOR — Kiosk NENÍ nakonfigurován ─────────────────────────"
    echo "  ! kiosk.conf nebyl nalezen"
    echo "  ! Kroky:"
    echo "    1. Zkopíruj kiosk.conf na /boot/firmware/kiosk.conf"
    echo "    2. Spusť: sudo bash /usr/local/bin/firstboot.sh"
fi
echo ""
echo "══════════════════════════════════════════════════════════════"
} | tee -a "$LOG" | tee "$REPORT"

# ─── Finální výstup ───────────────────────────────────────────────────────────
echo ""
if [[ ! -f "$KIOSK_CONF" ]]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  DŮLEŽITÉ: Kiosk ještě není plně nakonfigurován!${NC}"
    echo -e "${YELLOW}  1. Zkopíruj kiosk.conf na /boot/firmware/kiosk.conf${NC}"
    echo -e "${YELLOW}  2. Spusť: sudo bash /usr/local/bin/firstboot.sh${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Provisioning dokončen za ${TOTAL_MIN}m ${TOTAL_SEC}s${NC}"
    echo -e "${GREEN}  RPi se nyní restartuje → kiosk bude připraven${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    info "Rebootuji za 5 sekund..."
    sleep 5
    reboot
fi
