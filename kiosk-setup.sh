#!/usr/bin/env bash
# =============================================================================
# HA KioskOS — Průvodce první instalací
#
# Zkopíruj na boot partition SD karty spolu s kiosk.conf, pak po prvním
# SSH přihlášení spusť:
#   bash /boot/firmware/kiosk-setup.sh
# =============================================================================

KIOSK_CONF="/boot/firmware/kiosk.conf"
PROVISION_LOCAL="/boot/firmware/provision.sh"
PROVISION_URL="https://raw.githubusercontent.com/romankysely/ha-kiosk-os/main/provision.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

clear
echo ""
echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}  ║        HA KioskOS  —  Průvodce instalací             ║${NC}"
echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── Kontrola kiosk.conf ──────────────────────────────────────────────────────
if [[ -f "$KIOSK_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$KIOSK_CONF"
    echo -e "${GREEN}  ✓ kiosk.conf nalezen${NC}"
    echo ""
    echo -e "  ┌─── Konfigurace kiosku ──────────────────────────────"
    echo -e "  │  Hostname:  ${BOLD}${KIOSK_HOSTNAME:-NEDEFINO}${NC}"
    echo -e "  │  HA URL:    ${BOLD}${KIOSK_HA_URL:-NEDEFINO}${NC}"
    echo -e "  │  HA User:   ${BOLD}${KIOSK_HA_USERNAME:-NEDEFINO}${NC}"
    echo -e "  │  Dashboard: ${BOLD}${KIOSK_DASHBOARD_URL:-NEDEFINO}${NC}"
    echo -e "  │  Moduly:    ${BOLD}${KIOSK_MODULES:-výchozí}${NC}"
    echo -e "  └────────────────────────────────────────────────────"
    echo ""

    # Varování při chybějících klíčových hodnotách
    if [[ -z "${KIOSK_HA_URL:-}" || -z "${KIOSK_HA_TOKEN:-}" ]]; then
        echo -e "${YELLOW}  ⚠ VAROVÁNÍ: kiosk.conf neobsahuje HA URL nebo token.${NC}"
        echo -e "${YELLOW}    Kiosk se nenakonfiguruje správně — vrať se do HA Addonu.${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}  ⚠ kiosk.conf nenalezen na ${KIOSK_CONF}${NC}"
    echo ""
    echo -e "  Provisioning proběhne bez konfigurace kiosku."
    echo -e "  Kiosk bude po instalaci nutné nakonfigurovat manuálně."
    echo -e "  (zkopíruj kiosk.conf na /boot/firmware/ a spusť firstboot.sh)"
    echo ""
fi

echo -e "  Instalace potrvá přibližně ${BOLD}20–40 minut${NC} (apt + moduly)."
echo -e "  Po dokončení se RPi automaticky restartuje a kiosk bude připraven."
echo ""
echo -e "${YELLOW}  Nezavírej toto SSH okno po celou dobu instalace!${NC}"
echo ""

# ─── Interaktivní dotaz ───────────────────────────────────────────────────────
read -rp "  Spustit provisioning nyní? [Y/n]: " ANSWER
ANSWER="${ANSWER:-Y}"

if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${GREEN}  Spouštím provisioning...${NC}"
    echo ""
    sleep 1

    # Preferuj lokální provision.sh z boot partition, fallback na curl z main
    if [[ -f "$PROVISION_LOCAL" ]]; then
        exec sudo bash "$PROVISION_LOCAL"
    else
        exec bash <(curl -fsSL "$PROVISION_URL")
    fi
else
    echo ""
    echo -e "  Provisioning přerušen. Spusť jej manuálně:"
    echo ""
    echo -e "  ${BOLD}curl -fsSL ${PROVISION_URL} | sudo bash${NC}"
    echo ""
fi
