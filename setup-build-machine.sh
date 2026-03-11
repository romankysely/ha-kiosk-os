#!/usr/bin/env bash
# setup-build-machine.sh — Příprava build stroje pro ha-kiosk-os
# Spusť jako root: sudo bash setup-build-machine.sh
# Testováno na: Ubuntu Server 22.04 LTS (amd64)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ─── root check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Skript musí běžet jako root. Spusť: sudo bash $0"
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ha-kiosk-os — příprava build stroje            ║"
echo "║   Ubuntu 22.04 LTS · Synology VMM                ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ─── 1. System update ────────────────────────────────────────────────────────
info "Aktualizuji systémové balíčky..."
apt-get update -qq
apt-get upgrade -y -qq
ok "Systém aktualizován"

# ─── 2. Závislosti ───────────────────────────────────────────────────────────
info "Instaluji závislosti pro build..."

PACKAGES=(
    # Základní nástroje
    git
    curl
    wget
    xz-utils
    p7zip-full
    zip
    unzip
    jq
    python3

    # QEMU + ARM64 emulace
    qemu-user-static
    binfmt-support

    # Manipulace s disk image
    parted
    kpartx
    util-linux
    mount
    e2fsprogs
    fdisk

    # SSH (pro git push)
    openssh-client
)

apt-get install -y -qq "${PACKAGES[@]}"
ok "Závislosti nainstalovány"

# ─── 3. Aktivace binfmt pro ARM64 ────────────────────────────────────────────
info "Aktivuji binfmt ARM64 emulaci..."
systemctl restart systemd-binfmt 2>/dev/null || true

# Ověření
if update-binfmts --display qemu-aarch64 2>/dev/null | grep -q "enabled"; then
    ok "QEMU ARM64 binfmt: enabled"
else
    warn "binfmt pro qemu-aarch64 není enabled — zkus ručně:"
    warn "  sudo update-binfmts --enable qemu-aarch64"
fi

# ─── 4. Ověření qemu verze ───────────────────────────────────────────────────
info "Ověřuji qemu-aarch64-static..."
if command -v qemu-aarch64-static &>/dev/null; then
    QEMU_VER=$(qemu-aarch64-static --version | head -1)
    ok "qemu-aarch64-static: $QEMU_VER"
else
    error "qemu-aarch64-static nenalezen — instalace selhala?"
fi

# ─── 5. Git konfigurace (volitelné) ──────────────────────────────────────────
# Nastav pro uživatele který bude buildovat (ne root)
REAL_USER="${SUDO_USER:-}"
if [[ -n "$REAL_USER" ]]; then
    info "Kontroluji git config pro uživatele $REAL_USER..."
    GIT_EMAIL=$(sudo -u "$REAL_USER" git config --global user.email 2>/dev/null || true)
    GIT_NAME=$(sudo -u "$REAL_USER" git config --global user.name 2>/dev/null || true)
    if [[ -z "$GIT_EMAIL" || -z "$GIT_NAME" ]]; then
        warn "Git identita není nastavena. Nastav ji:"
        warn "  git config --global user.name 'Your Name'"
        warn "  git config --global user.email 'YOUR_EMAIL'"
    else
        ok "Git identita: $GIT_NAME <$GIT_EMAIL>"
    fi
fi

# ─── 6. Kontrola volného místa ───────────────────────────────────────────────
info "Kontroluji volné místo na disku..."
FREE_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ $FREE_GB -lt 15 ]]; then
    warn "Volné místo: ${FREE_GB} GB — doporučeno min. 15 GB pro build"
    warn "Build potřebuje: ~8 GB pro image + pracovní prostor"
else
    ok "Volné místo: ${FREE_GB} GB (dostatečné)"
fi

# ─── 7. Shrnutí ──────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✓  Build stroj připraven!                      ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Další kroky:"
echo ""
echo "  1. Klonuj repozitář:"
echo "     git clone https://github.com/romankysely/ha-kiosk-os.git"
echo "     cd ha-kiosk-os && git checkout dev"
echo ""
echo "  2. Uprav konfiguraci:"
echo "     nano config/build.conf"
echo "     # Nastav RPI_OS_URL a RPI_OS_SHA256"
echo ""
echo "  3. Spusť build:"
echo "     sudo ./build.sh"
echo ""
echo "Dokumentace: docs/ha-kiosk-builder.md"
echo ""
