# Modul: 02-vnc

Viz dokumentaci: [docs/modules/vnc.md](../../docs/modules/vnc.md)

## Soubory modulu

- `start_chroot_script` — bash skript spuštěný v chroot při buildu
- `files/` — soubory kopírované do image (struktura odpovídá /)

## Struktura files/

```
files/
└── etc/vnc/config.d/
    └── common.custom    ← SystemAuth, šifrování, port 5900, LAN only
```

## Stav

Implementováno v1.0.0
