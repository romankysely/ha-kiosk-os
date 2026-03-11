# Modul 05-ha-bootstrap

## Co dělá

Zajišťuje **automatickou konfiguraci kiosku při prvním startu** a jeho
registraci do HA Addonu (phone-home mechanismus).

## Životní cyklus firstboot

```
RPi se zapne poprvé
    ↓
systemd spustí kiosk-firstboot.service
    ↓
firstboot.sh zkontroluje /boot/firmware/kiosk.conf
    ↓ (soubor existuje)
Načte konfiguraci:
  - KIOSK_HOSTNAME
  - KIOSK_DASHBOARD_URL
  - KIOSK_HA_URL
  - KIOSK_HA_TOKEN
  - KIOSK_NETWORK (dhcp/static/wifi)
  - KIOSK_RESOLUTION
  - KIOSK_AUDIO_OUTPUT
    ↓
Nastaví hostname
    ↓
Nastaví síť (LAN DHCP / statická IP / WiFi)
    ↓
Phone-home: POST na HA Addon API
  → "Jsem online, moje MAC je xx:xx, čekám na SSH klíč"
    ↓
HA Addon odpoví:
  → SSH veřejný klíč pro tohoto kiosk
  → Potvrzení konfigurace
    ↓
Uloží SSH klíč do /home/pi/.ssh/authorized_keys
    ↓
Injektuje HA token do Chromium localStorage
  → Chromium se otevře přihlášený
    ↓
Smaže kiosk.conf z boot oddílu (bezpečnost!)
    ↓
Zakáže kiosk-firstboot.service (jednorázové)
    ↓
Reboot → kiosk je připraven
```

## kiosk.conf — formát

Generuje ho HA Addon. Nikdy nepíšeš ručně.

```bash
# kiosk.conf — generováno HA Addon Kiosk Builder
# TENTO SOUBOR BUDE SMAZÁN PO PRVNÍM STARTU

KIOSK_HOSTNAME="kiosk-01"
KIOSK_DASHBOARD_URL="http://192.168.1.100:8123/lovelace/kiosk"
KIOSK_HA_URL="http://192.168.1.100:8123"
KIOSK_HA_TOKEN="eyJ0eXAiOiJKV1QiLCJhbGci..."
KIOSK_NETWORK="dhcp"
KIOSK_WIFI_SSID=""
KIOSK_WIFI_PASSWORD=""
KIOSK_STATIC_IP=""
KIOSK_STATIC_GATEWAY=""
KIOSK_STATIC_DNS="8.8.8.8"
KIOSK_RESOLUTION="1920x1080"
KIOSK_ROTATION="0"
KIOSK_AUDIO_OUTPUT="hdmi0"
KIOSK_SNAPCAST_HOST=""
```

## HA token injection do Chromium

Chromium ukládá přihlášení do localStorage. Firstboot skript
zapíše token ještě před prvním spuštěním Chromia:

```bash
# /usr/local/bin/inject-ha-token.sh
PROFILE_DIR="/home/pi/.config/chromium/Default"
mkdir -p "$PROFILE_DIR"

# Vytvoří Local Storage záznam pro HA
python3 /usr/local/bin/inject-ha-token.py \
  --profile "$PROFILE_DIR" \
  --url "$KIOSK_HA_URL" \
  --token "$KIOSK_HA_TOKEN"
```

## Phone-home API volání

```bash
curl -X POST "$KIOSK_HA_URL/api/kiosk_builder/register" \
  -H "Authorization: Bearer $KIOSK_HA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "'$KIOSK_HOSTNAME'",
    "mac": "'$(cat /sys/class/net/eth0/address)'",
    "ip": "'$(hostname -I | awk '{print $1}')'",
    "version": "'$(cat /etc/ha-kiosk-os_version)'"
  }'
```

## Soubory

| Soubor | Popis |
|--------|-------|
| `/etc/systemd/system/kiosk-firstboot.service` | Systemd service (jednorázová) |
| `/usr/local/bin/firstboot.sh` | Hlavní firstboot skript |
| `/usr/local/bin/inject-ha-token.py` | Injekce HA tokenu do Chromium |
| `/etc/ha-kiosk-os_version` | Verze image |
| `/var/log/kiosk-firstboot.log` | Log prvního startu |

## Troubleshooting

### Firstboot se nespustil
```bash
sudo systemctl status kiosk-firstboot.service
cat /var/log/kiosk-firstboot.log
```

### kiosk.conf nenalezen
```bash
ls /boot/firmware/kiosk.conf
# Pokud chybí → zkopíruj znovu z HA Addonu na SD kartu (po reimage)
```

### Phone-home selhal (HA nedostupné)
```bash
# Ověř síť
ping -c 3 192.168.1.100

# Zkontroluj HA URL v kiosk.conf
grep KIOSK_HA_URL /var/log/kiosk-firstboot.log
```

## Changelog

| Verze | Změna |
|-------|-------|
| 1.0.0 | Phone-home, token injection |
