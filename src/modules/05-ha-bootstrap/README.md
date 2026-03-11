# Modul: 05-ha-bootstrap

Viz dokumentaci: [docs/modules/ha-bootstrap.md](../../docs/modules/ha-bootstrap.md)

## Soubory modulu

- `start_chroot_script` — bash skript spuštěný v chroot při buildu
- `files/` — soubory kopírované do image (struktura odpovídá /)

## Struktura files/

```
files/
├── etc/systemd/system/
│   └── kiosk-firstboot.service   ← jednorázová systemd service
└── usr/local/bin/
    ├── firstboot.sh              ← hlavní firstboot skript (10 kroků)
    └── inject-ha-token.py        ← Python: injektuje HA token do Chromiu
```

## Firstboot kroky

1. Načte `/boot/firmware/kiosk.conf`
2. Nastaví hostname
3. Konfiguruje síť (dhcp / static / wifi)
4. Nahradí `__DASHBOARD_URL__` v chromium-kiosk
5. Nahradí `__SNAPCAST_HOST__` v /etc/default/snapclient
6. Nastaví rozlišení a rotaci (xrandr v openbox autostart)
7. Phone-home → HA Addon API → dostane SSH klíč
8. Injektuje HA token do Chromium localStorage
9. **Smaže kiosk.conf** (bezpečnost — obsahuje HA token!)
10. Zakáže firstboot service → reboot

## Stav

Implementováno v1.0.0
