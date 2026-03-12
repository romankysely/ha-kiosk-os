#!/usr/bin/env bash
# HA KioskOS — Firstboot skript
# Spouštěn systemd službou kiosk-firstboot.service při prvním startu
# Čte kiosk.conf z boot oddílu a konfiguruje kiosk
set -euo pipefail

LOG="/var/log/kiosk-firstboot.log"
KIOSK_CONF="/boot/firmware/kiosk.conf"
CHROMIUM_KIOSK="/usr/local/bin/chromium-kiosk"
SNAPCLIENT_DEFAULTS="/etc/default/snapclient"

# ---------------------------------------------------------------------------
# Pomocná funkce pro logování
# ---------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG}"
}

log "=========================================="
log "HA KioskOS Firstboot zahájen"
log "=========================================="

# ---------------------------------------------------------------------------
# 1. Ověření existence kiosk.conf
# ---------------------------------------------------------------------------
if [ ! -f "${KIOSK_CONF}" ]; then
    log "CHYBA: ${KIOSK_CONF} nenalezen — přeskakuji firstboot"
    exit 1
fi

log "Načítám konfiguraci z ${KIOSK_CONF}..."
# shellcheck source=/dev/null
source "${KIOSK_CONF}"

# Výchozí hodnoty pro nepovinné proměnné
KIOSK_NETWORK="${KIOSK_NETWORK:-dhcp}"
KIOSK_RESOLUTION="${KIOSK_RESOLUTION:-1920x1080}"
KIOSK_ROTATION="${KIOSK_ROTATION:-0}"
KIOSK_AUDIO_OUTPUT="${KIOSK_AUDIO_OUTPUT:-hdmi0}"
KIOSK_SNAPCAST_HOST="${KIOSK_SNAPCAST_HOST:-}"
KIOSK_ADDON_URL="${KIOSK_ADDON_URL:-}"

log "Hostname:    ${KIOSK_HOSTNAME:-NEDEFINO}"
log "HA URL:      ${KIOSK_HA_URL:-NEDEFINO}"
log "HA User:     ${KIOSK_HA_USERNAME:-NEDEFINO}"
log "Addon URL:   ${KIOSK_ADDON_URL:-není nastaven}"
log "Dashboard:   ${KIOSK_DASHBOARD_URL:-NEDEFINO}"
log "Síť:         ${KIOSK_NETWORK}"
log "Rozlišení:   ${KIOSK_RESOLUTION} (rotace ${KIOSK_ROTATION})"
log "Audio:       ${KIOSK_AUDIO_OUTPUT}"
log "Snapcast:    ${KIOSK_SNAPCAST_HOST:-není nastaven}"

# ---------------------------------------------------------------------------
# 2. Hostname
# ---------------------------------------------------------------------------
if [ -n "${KIOSK_HOSTNAME:-}" ]; then
    log "Nastavuji hostname: ${KIOSK_HOSTNAME}..."
    hostnamectl set-hostname "${KIOSK_HOSTNAME}"
    # Aktualizovat /etc/hosts
    sed -i "s/127.0.1.1.*/127.0.1.1\t${KIOSK_HOSTNAME}/" /etc/hosts \
        || echo "127.0.1.1 ${KIOSK_HOSTNAME}" >> /etc/hosts
    log "Hostname nastaven OK"
fi

# ---------------------------------------------------------------------------
# 3. Síťová konfigurace
# ---------------------------------------------------------------------------
log "Konfiguruji síť (režim: ${KIOSK_NETWORK})..."

case "${KIOSK_NETWORK}" in
    dhcp|lan-dhcp)
        log "LAN DHCP — žádná změna (výchozí chování RPi OS)"
        ;;
    static|lan-static)
        if [ -n "${KIOSK_STATIC_IP:-}" ] && [ -n "${KIOSK_STATIC_GATEWAY:-}" ]; then
            log "Statická IP (LAN): ${KIOSK_STATIC_IP}, GW: ${KIOSK_STATIC_GATEWAY}"
            cat >> /etc/dhcpcd.conf <<DHCP_EOF

# HA KioskOS static IP (nastaveno při firstboot)
interface eth0
static ip_address=${KIOSK_STATIC_IP}/24
static routers=${KIOSK_STATIC_GATEWAY}
static domain_name_servers=${KIOSK_STATIC_DNS:-8.8.8.8}
DHCP_EOF
            log "Statická IP (LAN) nastavena OK"
        else
            log "VAROVÁNÍ: KIOSK_NETWORK=${KIOSK_NETWORK} ale IP/GW není nastavena — používám DHCP"
        fi
        ;;
    wifi|wifi-dhcp)
        if [ -n "${KIOSK_WIFI_SSID:-}" ]; then
            log "WiFi DHCP, SSID: ${KIOSK_WIFI_SSID}"
            cat > /etc/wpa_supplicant/wpa_supplicant.conf <<WIFI_EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=CZ

network={
    ssid="${KIOSK_WIFI_SSID}"
    psk="${KIOSK_WIFI_PASSWORD:-}"
    key_mgmt=WPA-PSK
}
WIFI_EOF
            chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
            log "WiFi DHCP konfigurace nastavena OK"
        else
            log "VAROVÁNÍ: KIOSK_NETWORK=${KIOSK_NETWORK} ale SSID není nastaven — používám eth0"
        fi
        ;;
    wifi-static)
        if [ -n "${KIOSK_WIFI_SSID:-}" ]; then
            log "WiFi statická IP, SSID: ${KIOSK_WIFI_SSID}, IP: ${KIOSK_STATIC_IP}"
            cat > /etc/wpa_supplicant/wpa_supplicant.conf <<WIFI_STATIC_EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=CZ

network={
    ssid="${KIOSK_WIFI_SSID}"
    psk="${KIOSK_WIFI_PASSWORD:-}"
    key_mgmt=WPA-PSK
}
WIFI_STATIC_EOF
            chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
            if [ -n "${KIOSK_STATIC_IP:-}" ] && [ -n "${KIOSK_STATIC_GATEWAY:-}" ]; then
                cat >> /etc/dhcpcd.conf <<DHCP_WIFI_EOF

# HA KioskOS static IP (WiFi, nastaveno při firstboot)
interface wlan0
static ip_address=${KIOSK_STATIC_IP}/24
static routers=${KIOSK_STATIC_GATEWAY}
static domain_name_servers=${KIOSK_STATIC_DNS:-8.8.8.8}
DHCP_WIFI_EOF
                log "WiFi statická IP nastavena OK"
            else
                log "VAROVÁNÍ: wifi-static ale IP/GW není nastavena — WiFi bude DHCP"
            fi
        else
            log "VAROVÁNÍ: KIOSK_NETWORK=wifi-static ale SSID není nastaven — používám eth0"
        fi
        ;;
    *)
        log "VAROVÁNÍ: Neznámý typ sítě '${KIOSK_NETWORK}' — používám DHCP"
        ;;
esac

# ---------------------------------------------------------------------------
# 4. Dashboard URL — nahradit placeholder v chromium-kiosk
# ---------------------------------------------------------------------------
if [ -n "${KIOSK_DASHBOARD_URL:-}" ] && [ -f "${CHROMIUM_KIOSK}" ]; then
    log "Nastavuji Dashboard URL: ${KIOSK_DASHBOARD_URL}..."
    sed -i "s|__DASHBOARD_URL__|${KIOSK_DASHBOARD_URL}|g" "${CHROMIUM_KIOSK}"
    log "Dashboard URL nastavena OK"
else
    log "VAROVÁNÍ: Dashboard URL není nastavena nebo chromium-kiosk nenalezen"
fi

# ---------------------------------------------------------------------------
# 5. Snapcast host — nahradit placeholder v /etc/default/snapclient
# ---------------------------------------------------------------------------
if [ -n "${KIOSK_SNAPCAST_HOST:-}" ] && [ -f "${SNAPCLIENT_DEFAULTS}" ]; then
    log "Nastavuji Snapcast host: ${KIOSK_SNAPCAST_HOST}..."
    sed -i "s|__SNAPCAST_HOST__|${KIOSK_SNAPCAST_HOST}|g" "${SNAPCLIENT_DEFAULTS}"
    log "Snapcast host nastaven OK"
elif [ -f "${SNAPCLIENT_DEFAULTS}" ]; then
    log "Snapcast host není nastaven — deaktivuji snapclient"
    sed -i "s/START_SNAPCLIENT=yes/START_SNAPCLIENT=no/" "${SNAPCLIENT_DEFAULTS}"
fi

# ---------------------------------------------------------------------------
# 6. Rozlišení a rotace (přidat xrandr do openbox autostart)
# ---------------------------------------------------------------------------
OPENBOX_AUTOSTART="/home/pi/.config/openbox/autostart"
if [ -f "${OPENBOX_AUTOSTART}" ]; then
    log "Nastavuji rozlišení ${KIOSK_RESOLUTION} (rotace ${KIOSK_ROTATION})..."

    # Rotation map: 0=normal, 1=left, 2=inverted, 3=right
    case "${KIOSK_ROTATION}" in
        0) XRANDR_ROTATE="normal" ;;
        1) XRANDR_ROTATE="left" ;;
        2) XRANDR_ROTATE="inverted" ;;
        3) XRANDR_ROTATE="right" ;;
        *) XRANDR_ROTATE="normal" ;;
    esac

    # Vložit xrandr na začátek autostart (před ostatní příkazy)
    TMPFILE=$(mktemp)
    {
        echo "# Rozlišení a rotace (nastaveno při firstboot)"
        echo "xrandr --output HDMI-1 --mode ${KIOSK_RESOLUTION} --rotate ${XRANDR_ROTATE} &"
        echo ""
        cat "${OPENBOX_AUTOSTART}"
    } > "${TMPFILE}"
    mv "${TMPFILE}" "${OPENBOX_AUTOSTART}"
    chown 1000:1000 "${OPENBOX_AUTOSTART}"
    log "Rozlišení nastaveno OK"
fi

# ---------------------------------------------------------------------------
# 7. Phone-home — registrace u HA Kiosk Builder Addonu, získání SSH klíče
#    Addon musí být dostupný na KIOSK_ADDON_URL (výchozí port 8099)
# ---------------------------------------------------------------------------
PHONE_HOME_URL="${KIOSK_ADDON_URL:-${KIOSK_HA_URL}:8099}"

if [ -n "${PHONE_HOME_URL:-}" ]; then
    log "Phone-home: registrace u Kiosk Builder Addonu (${PHONE_HOME_URL})..."

    REGISTER_PAYLOAD=$(cat <<JSON_EOF
{
    "hostname": "${KIOSK_HOSTNAME:-kiosk}",
    "ha_username": "${KIOSK_HA_USERNAME:-}",
    "dashboard_url": "${KIOSK_DASHBOARD_URL:-}",
    "mac": "$(cat /sys/class/net/eth0/address 2>/dev/null || echo 'unknown')",
    "ip": "$(hostname -I | awk '{print $1}')"
}
JSON_EOF
)

    RESPONSE=$(curl -s --connect-timeout 15 --max-time 30 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "${REGISTER_PAYLOAD}" \
        "${PHONE_HOME_URL}/api/register" 2>&1) || true

    # Extrahovat SSH klíč z odpovědi (pokud HA Addon odpoví)
    SSH_KEY=$(echo "${RESPONSE}" | jq -r '.ssh_public_key // empty' 2>/dev/null || true)

    if [ -n "${SSH_KEY}" ]; then
        log "SSH klíč přijat od HA Addonu — ukládám..."
        mkdir -p /home/pi/.ssh
        chmod 700 /home/pi/.ssh
        echo "${SSH_KEY}" >> /home/pi/.ssh/authorized_keys
        chmod 600 /home/pi/.ssh/authorized_keys
        chown -R 1000:1000 /home/pi/.ssh
        log "SSH klíč uložen OK"
    else
        log "VAROVÁNÍ: HA Addon neodpověděl nebo nevrátil SSH klíč"
        log "Response: ${RESPONSE:0:200}"
        log "SSH přístup bude nutné nastavit ručně"
    fi
else
    log "VAROVÁNÍ: KIOSK_ADDON_URL ani KIOSK_HA_URL není nastavena — přeskakuji phone-home"
fi

# ---------------------------------------------------------------------------
# 8. Injektovat HA token do Chromium (pro auto-login do HA)
# ---------------------------------------------------------------------------
if [ -n "${KIOSK_HA_TOKEN:-}" ] && [ -n "${KIOSK_HA_URL:-}" ]; then
    log "Injektuji HA token do Chromium localStorage..."
    /usr/local/bin/inject-ha-token.py \
        --token "${KIOSK_HA_TOKEN}" \
        --ha-url "${KIOSK_HA_URL}" \
        --user pi \
        >> "${LOG}" 2>&1 \
        && log "HA token injektován OK" \
        || log "VAROVÁNÍ: Injekce HA tokenu selhala (Chromium si token nastaví po prvním přihlášení)"
else
    log "HA token/URL není nastaven — přeskakuji token injection"
fi

# ---------------------------------------------------------------------------
# 9. Bezpečnost — smazat kiosk.conf z boot oddílu
#    kiosk.conf obsahuje HA token — nesmí zůstat na přístupném oddílu
# ---------------------------------------------------------------------------
log "Mažu ${KIOSK_CONF} (bezpečnost — obsahuje HA token)..."
rm -f "${KIOSK_CONF}"
sync
log "kiosk.conf smazán OK"

# ---------------------------------------------------------------------------
# 10. Zakázat firstboot service (jednorázová)
# ---------------------------------------------------------------------------
log "Zakazuji kiosk-firstboot.service..."
systemctl disable kiosk-firstboot.service

log "=========================================="
log "HA KioskOS Firstboot dokončen úspěšně!"
log "Restartuji za 5 sekund..."
log "=========================================="

sleep 5
reboot
