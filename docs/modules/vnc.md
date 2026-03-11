# Modul 02-vnc

## Co dělá

Instaluje a konfiguruje **RealVNC Server** pro vzdálený grafický přístup ke kiosku.
RealVNC je výrazně rychlejší a stabilnější než alternativy (x11vnc apod.).

## Proč RealVNC (ne x11vnc)

| | x11vnc | RealVNC |
|--|--------|---------|
| Rychlost | pomalá | rychlá |
| Stabilita | občasné pády | stabilní |
| Autentizace | heslo v plain textu | systémový účet pi |
| Šifrování | volitelné | výchozí |
| Integrace se systemd | ne | ano |

## Co se instaluje

```
realvnc-vnc-server
```

## Konfigurace

### Systemd service
```
/etc/systemd/system/multi-user.target.wants/vncserver-x11-serviced.service
```
Automaticky spustí VNC server při každém startu.

### Parametry připojení
- **Port**: 5900 (výchozí VNC)
- **Přihlášení**: systémový účet `pi` + heslo nastavené v RPi Imager
- **Šifrování**: TLS (výchozí)

## Jak se připojit

### RealVNC Viewer (doporučeno)
1. Stáhni [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/)
2. Přidej: `192.168.1.101:5900` (nebo hostname `kiosk.local`)
3. Přihlásit: `pi` + heslo

### Z HA Addonu (plánovaná funkce)
- Klikni na kiosk → "VNC Console"
- Otevře se noVNC v prohlížeči

## Poznámky

- VNC přístup je **primárně pro správu**, ne pro každodenní použití
- Chromium kiosk běží na DISPLAY :0 — VNC zobrazuje tuto session
- Pi5 napájení: pokud máš monitor připojen přes USB-C, VNC funguje i bez monitoru

## Troubleshooting

### VNC se nepřipojí
```bash
# Status service
sudo systemctl status vncserver-x11-serviced

# Restart
sudo systemctl restart vncserver-x11-serviced

# Port naslouchá?
sudo netstat -tlnp | grep 5900
```

### Šedá obrazovka v VNC
```bash
# X server neběží nebo Openbox neběžel
sudo systemctl status display-manager
pgrep openbox || echo "Openbox neběží"
```

## Changelog

| Verze | Změna |
|-------|-------|
| 1.0.0 | Počáteční verze, RealVNC |
