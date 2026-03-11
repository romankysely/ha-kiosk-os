# Modul: 04-audio

Viz dokumentaci: [docs/modules/audio.md](../../docs/modules/audio.md)

## Soubory modulu

- `start_chroot_script` — bash skript spuštěný v chroot při buildu
- `files/` — soubory kopírované do image (struktura odpovídá /)

## Struktura files/

```
files/
└── etc/default/
    └── snapclient    ← SNAPCLIENT_OPTS s placeholder __SNAPCAST_HOST__
```

## Audio flow

```
HA / Music Assistant → Snapcast server (192.168.1.100)
  → LAN stream → snapclient (RPi5)
  → PipeWire (ALSA compat) → HDMI audio výstup
```

`__SNAPCAST_HOST__` se nahradí při firstboot z `KIOSK_SNAPCAST_HOST` v kiosk.conf.

## Stav

Implementováno v1.0.0
