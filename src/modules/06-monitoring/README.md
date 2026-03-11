# Modul: 06-monitoring

Viz dokumentaci: [docs/modules/monitoring.md](../../docs/modules/monitoring.md)

## Soubory modulu

- `start_chroot_script` — bash skript spuštěný v chroot při buildu
- `files/` — soubory kopírované do image (struktura odpovídá /)

## Struktura files/

```
files/
└── etc/
    ├── glances/
    │   └── glances.conf      ← limity CPU/RAM/disk/teplota, interval obnovy
    └── systemd/system/
        └── glances.service   ← web server na portu 61208
```

## Přístup

```
http://192.168.1.101:61208    ← přímá IP
http://kiosk.local:61208     ← přes mDNS hostname
```

Bez hesla — chráněno pouze Unifi firewallem (LAN only).

## Stav

Implementováno v1.0.0
