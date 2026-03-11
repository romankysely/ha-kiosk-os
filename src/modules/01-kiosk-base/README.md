# Modul: 01-kiosk-base

Viz dokumentaci: [docs/modules/kiosk-base.md](../../docs/modules/kiosk-base.md)

## Soubory modulu

- `start_chroot_script` — bash skript spuštěný v chroot při buildu
- `files/` — soubory kopírované do image (struktura odpovídá /)

## Struktura files/

```
files/
├── etc/
│   ├── chromium-browser/customizations/
│   │   └── 01-hw-video              ← HW video dekódování flagy
│   └── systemd/system/
│       ├── getty@tty1.service.d/
│       │   └── autologin.conf       ← autologin pi na TTY1
│       └── kiosk-watchdog.service   ← watchdog systemd unit
├── home/pi/
│   ├── .bash_profile                ← spustí startx na TTY1
│   ├── .xinitrc                     ← spustí openbox-session
│   └── .config/openbox/
│       ├── autostart                ← xset, unclutter, chromium-kiosk
│       └── rc.xml                   ← bez dekorací, vše maximalizováno
└── usr/local/bin/
    ├── chromium-kiosk               ← Chromium wrapper (HW video, flagy)
    └── kiosk-watchdog.sh            ← watchdog skript
```

## Stav

Implementováno v1.0.0
