# Modul 06-monitoring

## Co dělá

Instaluje nástroje pro vzdálený monitoring kiosku:
- **Glances** — webový přehled systému (CPU, RAM, disk, síť, procesy)
- **Watchdog** — automatický restart Chromium při pádu

## Glances

### Co zobrazuje
- CPU utilization (včetně teplot Pi5)
- RAM usage
- Disk I/O a utilizace
- Síťový provoz
- Běžící procesy
- Docker (pokud by byl nainstalován)

### Přístup
```
http://kiosk-hostname.local:61208
http://192.168.1.101:61208
```

### Systemd service
```
/etc/systemd/system/glances.service
```

Glances běží jako web server na portu 61208.
Přístupné z lokální sítě bez hesla (nastavitelné).

### Integrace s HA

Glances lze přidat jako HA integration:
1. HA → Settings → Integrations → Add → Glances
2. Host: `192.168.1.101`, Port: `61208`
3. Zobrazí se senzory: CPU, RAM, disk, teplota

### Konfigurace
`/etc/glances/glances.conf`:
```ini
[global]
check_update=false

[webserver]
host=0.0.0.0
port=61208
```

## Watchdog

### Jak funguje

```
kiosk-watchdog.service (systemd)
    → spustí kiosk-watchdog.sh jako daemon
    → každých 15 sekund:
        pgrep chromium-browser?
        NE → spustí chromium-kiosk
        ANO → čekej dalších 15s
```

### Proč i Openbox autostart nestačí

Openbox spustí Chromium při startu X serveru.
Watchdog hlídá **průběžně za provozu** — pokud Chromium spadne
z jakéhokoliv důvodu (OOM killer, crash, pád WebGL), watchdog ho
restartuje do 15 sekund bez nutnosti rebootu.

### Log

```bash
cat /var/log/kiosk-watchdog.log
# Příklad:
# 2026-03-10 10:15:23: Chromium neběží, spouštím...
# 2026-03-10 10:15:38: Chromium běží OK
```

### Manuální restart Chromium

```bash
# Přes SSH — zabije Chromium, watchdog ho spustí znovu
pkill chromium-browser
# watchdog spustí nový do 15s
```

### Soubory

| Soubor | Popis |
|--------|-------|
| `/etc/systemd/system/kiosk-watchdog.service` | Systemd service |
| `/usr/local/bin/kiosk-watchdog.sh` | Watchdog skript |
| `/var/log/kiosk-watchdog.log` | Log |

## Troubleshooting

### Glances nedostupné
```bash
sudo systemctl status glances
sudo systemctl restart glances
journalctl -u glances -n 30
```

### Watchdog nefunguje
```bash
sudo systemctl status kiosk-watchdog
# Ručně otestuj
pkill chromium-browser
sleep 20
pgrep chromium-browser && echo "OK" || echo "Watchdog nefunguje!"
```

### Chromium se opakovaně restartuje
```bash
# Zjisti příčinu pádu
cat /var/log/kiosk-watchdog.log | grep "spouštím"
DISPLAY=:0 chromium-kiosk 2>&1 | tail -30
# Pravděpodobné příčiny:
# - Nedostatek RAM (zkontroluj free -h)
# - OOM killer (dmesg | grep -i "killed process")
# - Chyba v HA dashboard URL
```

## Changelog

| Verze | Změna |
|-------|-------|
| 1.0.0 | Glances + Watchdog |
