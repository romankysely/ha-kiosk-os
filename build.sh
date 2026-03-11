#!/usr/bin/env bash
# =============================================================================
# HA KioskOS — Hlavní build skript
# Použití: sudo ./build.sh [--keep-workspace] [--skip-download] [--modules M1,M2]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/build.conf"
LOG_FILE="$SCRIPT_DIR/build.log"

# Barvy
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${BLUE}==============================${NC}" | tee -a "$LOG_FILE"
            echo -e "${BLUE}  $*${NC}" | tee -a "$LOG_FILE"
            echo -e "${BLUE}==============================${NC}" | tee -a "$LOG_FILE"; }

# ============================================================================
# Parsování argumentů
# ============================================================================
SKIP_DOWNLOAD=false
OVERRIDE_KEEP_WORKSPACE=""
OVERRIDE_MODULES=""

for arg in "$@"; do
    case "$arg" in
        --keep-workspace)   OVERRIDE_KEEP_WORKSPACE="true" ;;
        --skip-download)    SKIP_DOWNLOAD=true ;;
        --modules=*)        OVERRIDE_MODULES="${arg#*=}" ;;
        --help|-h)
            echo "Použití: sudo $0 [možnosti]"
            echo "  --keep-workspace   Zachová workspace po buildu (pro debugging)"
            echo "  --skip-download    Přeskočí stažení RPi OS (pokud již existuje)"
            echo "  --modules=M1,M2    Přepíše seznam modulů z build.conf"
            exit 0
            ;;
    esac
done

# ============================================================================
section "Kontrola předpokladů"
# ============================================================================

[[ $EUID -eq 0 ]] || error "Spusť jako root: sudo $0"
[[ -f "$CONFIG_FILE" ]] || error "Nenalezen config/build.conf"

# Načti konfiguraci
source "$CONFIG_FILE"

# Přepisy z CLI argumentů
[[ -n "$OVERRIDE_KEEP_WORKSPACE" ]] && KEEP_WORKSPACE="$OVERRIDE_KEEP_WORKSPACE"
if [[ -n "$OVERRIDE_MODULES" ]]; then
    IFS=',' read -ra MODULES <<< "$OVERRIDE_MODULES"
fi

# Zkontroluj povinné závislosti
MISSING_DEPS=()
for cmd in wget xz git parted e2fsck resize2fs losetup; do
    command -v "$cmd" &>/dev/null || MISSING_DEPS+=("$cmd")
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    error "Chybějící závislosti: ${MISSING_DEPS[*]}\nNainstaluj: sudo apt-get install -y parted e2fsprogs util-linux wget xz-utils git"
fi

# Zkontroluj qemu pro ARM64 emulaci
if ! command -v qemu-aarch64-static &>/dev/null; then
    error "Chybí qemu-aarch64-static.\nNainstaluj: sudo apt-get install -y qemu-user-static binfmt-support"
fi

# Zkontroluj qemu binfmt registraci
if ! update-binfmts --display qemu-aarch64 2>/dev/null | grep -q "enabled"; then
    error "qemu-aarch64 binfmt není enabled.\nSpusť: sudo systemctl restart systemd-binfmt\nnebo: sudo update-binfmts --enable qemu-aarch64"
fi

info "Všechny předpoklady splněny"
info "Image verze: ${IMAGE_VERSION}"
info "Moduly (${#MODULES[@]}): ${MODULES[*]}"

# ============================================================================
section "Příprava prostředí"
# ============================================================================

mkdir -p "$SCRIPT_DIR/$OUTPUT_DIR"
mkdir -p "$SCRIPT_DIR/$WORKSPACE_DIR"

# Reset logu
echo "=== HA KioskOS Build log — $(date) ===" > "$LOG_FILE"
info "Build log: $LOG_FILE"

# ============================================================================
section "Stažení a ověření RPi OS"
# ============================================================================

IMG_ARCHIVE="$SCRIPT_DIR/$WORKSPACE_DIR/raspios-lite-arm64.img.xz"
IMG_FILE="$SCRIPT_DIR/$WORKSPACE_DIR/raspios-lite-arm64.img"

if [[ "$SKIP_DOWNLOAD" == "true" ]] && [[ -f "$IMG_FILE" ]]; then
    info "--skip-download: Používám existující obraz: $IMG_FILE"
elif [[ -f "$IMG_FILE" ]]; then
    info "RPi OS obraz již existuje: $IMG_FILE"
else
    # Stažení archivu
    if [[ -f "$IMG_ARCHIVE" ]]; then
        info "Archiv již stažen: $IMG_ARCHIVE"
    else
        info "Stahuji RPi OS Lite 64-bit (arm64, Bookworm)..."
        wget -O "$IMG_ARCHIVE" "$RPI_OS_URL" \
            --progress=bar:force \
            --show-progress \
            2>&1 | tee -a "$LOG_FILE"
    fi

    # SHA256 verifikace (přeskočí pokud je placeholder nebo prázdné)
    if [[ -n "${RPI_OS_SHA256:-}" ]] && [[ "$RPI_OS_SHA256" != "sha256:bla_bla" ]] && [[ "$RPI_OS_SHA256" != *"bla"* ]]; then
        info "Ověřuji SHA256 checksum..."
        EXPECTED_SHA256="${RPI_OS_SHA256#sha256:}"
        ACTUAL_SHA256=$(sha256sum "$IMG_ARCHIVE" | awk '{print $1}')
        if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
            rm -f "$IMG_ARCHIVE"
            error "SHA256 nesouhlasí!\n  Očekáváno: $EXPECTED_SHA256\n  Skutečné:  $ACTUAL_SHA256\nSouborarchiv byl smazán."
        fi
        info "SHA256 OK: $ACTUAL_SHA256"
    else
        warn "SHA256 verifikace přeskočena (RPI_OS_SHA256 není nastaven v build.conf)"
        warn "Doporučujeme doplnit SHA256 pro bezpečný build!"
    fi

    # Dekomprese
    # OPRAVA: xz nemá flag -o; používáme --stdout přesměrovaný do cílového souboru
    info "Rozbaluji obraz (může trvat 2–5 minut)..."
    xz --decompress --keep --stdout "$IMG_ARCHIVE" > "$IMG_FILE"
    info "Rozbaleno: $IMG_FILE ($(du -sh "$IMG_FILE" | cut -f1))"
fi

# ============================================================================
section "Příprava build image + resize rootfs"
# ============================================================================

BUILD_IMG="$SCRIPT_DIR/$WORKSPACE_DIR/build.img"
MOUNT_DIR="$SCRIPT_DIR/$WORKSPACE_DIR/mnt"
mkdir -p "$MOUNT_DIR"

# Pracovní kopie (originál zachovat pro opakované buildy)
info "Kopíruji base image..."
cp "$IMG_FILE" "$BUILD_IMG"

# Rozšíření image o EXTRA_SIZE_GB (výchozí 4 GB) pro naše balíčky
EXTRA_GB="${EXTRA_SIZE_GB:-4}"
info "Rozšiřuji image o ${EXTRA_GB} GB pro balíčky modulů..."
truncate -s "+${EXTRA_GB}G" "$BUILD_IMG"

# Loop mount
LOOP_DEV=$(losetup --find --show --partscan "$BUILD_IMG")
info "Loop device: $LOOP_DEV"
sleep 2
partprobe "$LOOP_DEV" 2>/dev/null || true
sleep 1

# Resize oddílu 2 (rootfs) na celý dostupný prostor
info "Resize partition 2 na celý disk..."
parted -s "$LOOP_DEV" resizepart 2 100%
sleep 1

# Resize filesystem
info "Kontrola a resize ext4 filesystemu..."
e2fsck -fp "${LOOP_DEV}p2" || true
resize2fs "${LOOP_DEV}p2"
info "Resize hotov: $(lsblk -o SIZE "${LOOP_DEV}p2" --noheadings | tr -d ' ')"

# ============================================================================
section "Mount a setup chroot"
# ============================================================================

# Mount rootfs a boot oddíl
mount "${LOOP_DEV}p2" "$MOUNT_DIR"
if mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot/firmware" 2>/dev/null; then
    BOOT_MOUNT="$MOUNT_DIR/boot/firmware"
else
    mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot"
    BOOT_MOUNT="$MOUNT_DIR/boot"
fi
info "Boot oddíl namountován na: $BOOT_MOUNT"

# Bind mounts pro chroot (vč. /dev/pts pro pty a /dev/shm pro sdílená paměť)
mount --bind /dev          "$MOUNT_DIR/dev"
mount --bind /dev/pts      "$MOUNT_DIR/dev/pts"
mount --bind /dev/shm      "$MOUNT_DIR/dev/shm"
mount --bind /proc         "$MOUNT_DIR/proc"
mount --bind /sys          "$MOUNT_DIR/sys"

# Zkopíruj qemu pro ARM64 emulaci v chroot
cp /usr/bin/qemu-aarch64-static "$MOUNT_DIR/usr/bin/"

# DNS pro apt-get v chroot (KRITICKÉ — bez toho apt-get selže)
cp /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"
info "resolv.conf zkopírován do chroot (DNS pro apt-get)"

# ld.so.preload — deaktivace v chroot (zabraňuje chybám při ARM64 emulaci)
if [[ -f "$MOUNT_DIR/etc/ld.so.preload" ]]; then
    mv "$MOUNT_DIR/etc/ld.so.preload" "$MOUNT_DIR/etc/ld.so.preload.disabled"
    info "ld.so.preload deaktivován (bude obnoven po buildu)"
fi

# ============================================================================
# Cleanup funkce — volána při EXIT (normálním i chybovém)
# ============================================================================
cleanup() {
    local exit_code=$?
    info "Spouštím cleanup..."

    # Obnov ld.so.preload
    if [[ -f "$MOUNT_DIR/etc/ld.so.preload.disabled" ]]; then
        mv "$MOUNT_DIR/etc/ld.so.preload.disabled" "$MOUNT_DIR/etc/ld.so.preload" 2>/dev/null || true
    fi

    # Smaž qemu z image (nemá být ve výsledku)
    rm -f "$MOUNT_DIR/usr/bin/qemu-aarch64-static" 2>/dev/null || true

    # Unmount v opačném pořadí
    umount "$MOUNT_DIR/dev/shm"      2>/dev/null || true
    umount "$MOUNT_DIR/dev/pts"      2>/dev/null || true
    umount "$MOUNT_DIR/dev"          2>/dev/null || true
    umount "$MOUNT_DIR/proc"         2>/dev/null || true
    umount "$MOUNT_DIR/sys"          2>/dev/null || true
    umount "$MOUNT_DIR/boot/firmware" 2>/dev/null || true
    umount "$MOUNT_DIR/boot"         2>/dev/null || true
    umount "$MOUNT_DIR"              2>/dev/null || true
    losetup -d "$LOOP_DEV"          2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        warn "Build selhal (exit code: $exit_code). Viz $LOG_FILE"
    fi
}
trap cleanup EXIT

# ============================================================================
section "Aplikace modulů"
# ============================================================================

# Verze image
echo "$IMAGE_VERSION" > "$MOUNT_DIR/etc/ha-kiosk-os_version"
info "Image verze $IMAGE_VERSION zapsána do /etc/ha-kiosk-os_version"

MODULE_OK=0
MODULE_FAIL=0

for MODULE in "${MODULES[@]}"; do
    section "Modul: $MODULE"
    MODULE_DIR="$SCRIPT_DIR/src/modules/$MODULE"

    if [[ ! -d "$MODULE_DIR" ]]; then
        warn "Modul $MODULE nenalezen v $MODULE_DIR — přeskakuji"
        continue
    fi

    # 1. Zkopíruj files/ do image (zachovej oprávnění)
    if [[ -d "$MODULE_DIR/files" ]] && [[ -n "$(ls -A "$MODULE_DIR/files")" ]]; then
        info "Kopíruji files/ do image..."
        cp -a "$MODULE_DIR/files/." "$MOUNT_DIR/"
        info "files/ zkopírovány OK"
    else
        info "Žádné files/ pro $MODULE (přeskakuji)"
    fi

    # 2. Spusť chroot skript
    if [[ -f "$MODULE_DIR/start_chroot_script" ]]; then
        info "Spouštím start_chroot_script v ARM64 chroot..."
        CHROOT_SCRIPT="/tmp/chroot_${MODULE}.sh"
        cp "$MODULE_DIR/start_chroot_script" "$MOUNT_DIR${CHROOT_SCRIPT}"
        chmod +x "$MOUNT_DIR${CHROOT_SCRIPT}"

        if chroot "$MOUNT_DIR" "${CHROOT_SCRIPT}" 2>&1 | tee -a "$LOG_FILE"; then
            info "Modul $MODULE dokončen ✓"
            MODULE_OK=$((MODULE_OK + 1))
        else
            error "Modul $MODULE SELHAL! Viz $LOG_FILE"
            MODULE_FAIL=$((MODULE_FAIL + 1))
        fi

        rm -f "$MOUNT_DIR${CHROOT_SCRIPT}"
    else
        warn "start_chroot_script nenalezen pro $MODULE — přeskakuji"
    fi
done

info "Moduly: $MODULE_OK OK, $MODULE_FAIL selhalo"

# ============================================================================
section "Finalizace image"
# ============================================================================

# Spusť cleanup ručně (před přejmenováním souboru)
cleanup
trap - EXIT

# Zmenšení image na minimální velikost (volitelné — ušetří místo)
if [[ "${COMPRESS_IMAGE:-false}" == "true" ]]; then
    info "Komprese výsledného image..."
    xz -T0 -9 "$BUILD_IMG"
    BUILD_IMG="${BUILD_IMG}.xz"
    OUTPUT_EXT=".img.xz"
else
    OUTPUT_EXT=".img"
fi

# Výsledný název souboru
DATE=$(date +%Y-%m-%d)
OUTPUT_IMG="$SCRIPT_DIR/$OUTPUT_DIR/${IMAGE_NAME}-${DATE}${OUTPUT_EXT}"

mv "$BUILD_IMG" "$OUTPUT_IMG"
info "Image přesunut: $OUTPUT_IMG"

# Cleanup workspace
if [[ "$KEEP_WORKSPACE" != "true" ]]; then
    rm -rf "$SCRIPT_DIR/$WORKSPACE_DIR"
    info "Workspace smazán"
else
    info "Workspace zachován (KEEP_WORKSPACE=true): $SCRIPT_DIR/$WORKSPACE_DIR"
fi

# ============================================================================
section "Build dokončen"
# ============================================================================

IMG_SIZE=$(du -sh "$OUTPUT_IMG" | cut -f1)
BUILD_END=$(date)

echo ""
echo "=================================================="
echo -e "  ${GREEN}✓ Build úspěšný!${NC}"
echo "  Image:    $OUTPUT_IMG"
echo "  Velikost: $IMG_SIZE"
echo "  Verze:    $IMAGE_VERSION"
echo "  Čas:      $BUILD_END"
echo ""
echo "  Další kroky:"
echo "  1. Flashni v RPi Imager jako Custom OS"
echo "     - Device: Raspberry Pi 5"
echo "     - OS: Use custom → $(basename "$OUTPUT_IMG")"
echo "     - Username: pi, SSH: enabled"
echo "  2. Vygeneruj kiosk.conf v HA Addonu"
echo "  3. Zkopíruj kiosk.conf na boot oddíl SD karty"
echo "  4. Vlož SD kartu do RPi 5 a zapni"
echo "     → Firstboot proběhne automaticky (5–10 min)"
echo "=================================================="

echo ""
info "Build log uložen: $LOG_FILE"
