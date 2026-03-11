# HA KioskOS

Specializovaná 64-bit RPi distribuce pro Home Assistant kiosky.
Postavena na čistém RPi OS Lite 64-bit s modulárními komponentami pro HA kiosk nasazení.

## Co to je

Vlastní RPi OS image postavený na čistém **Raspberry Pi OS Lite 64-bit (Bookworm)**,
rozšířený o předinstalované moduly pro HA kiosk nasazení.

## Klíčové vlastnosti

| Funkce | Detail |
|--------|--------|
| 64-bit (aarch64) | Plná podpora Claude Code, Node.js 20+ |
| Chromium kiosk | Autologin → HA dashboard, bez interakce uživatele |
| RealVNC server | Vzdálená správa bez fyzického přístupu |
| Claude Code | AI asistent přímo na kiosku pro vzdálené úpravy |
| PipeWire + Snapcast | Multi-room audio z HA |
| HW video dekódování | Pi5 H.264/HEVC dekodér pro WebRTC kamery |
| Watchdog | Automatický restart Chromium při pádu |
| Glances | Vzdálený monitoring systému |
| HA Bootstrap | Phone-home registrace po prvním startu |

## Rychlý start (Provisioning — doporučeno)

Viz [docs/02-how-to-build.md](docs/02-how-to-build.md)

```
1. Flash stock RPi OS Lite 64-bit přes RPi Imager (user=pi, SSH enabled)
2. Na boot partition zkopíruj kiosk.conf (generovaný z HA Addonu)
3. SSH do RPi → sudo bash provision.sh (nebo curl | sudo bash)
4. Čekej ~20-40 min → automatický reboot → kiosk hotový
```

## Dokumentace

- [docs/00-overview.md](docs/00-overview.md) — architektura projektu
- [docs/01-git-architecture.md](docs/01-git-architecture.md) — git struktura a workflow
- [docs/02-how-to-build.md](docs/02-how-to-build.md) — jak sestavit image
- [docs/03-adding-module.md](docs/03-adding-module.md) — jak přidat nový modul
- [docs/04-upgrade-upstream.md](docs/04-upgrade-upstream.md) — jak upgradovat RPi OS
- [docs/05-ha-addon.md](docs/05-ha-addon.md) — HA Addon Kiosk Builder
- [docs/modules/](docs/modules/) — dokumentace jednotlivých modulů

## Bezpečnost a soukromí

**Tento repozitář neobsahuje žádné citlivé informace.**
Vše specifické pro konkrétní instalaci (WiFi, HA URL, tokeny, IP adresy)
se generuje za běhu přes HA Addon a nikdy se nedostane do gitu.

Viz [docs/06-security.md](docs/06-security.md)

## Struktura repozitáře

```
ha-kiosk-os/
├── provision.sh       # Primární nasazení: stock RPi OS → hotový kiosk
├── build.sh           # Záloha: Ubuntu VM + QEMU → vlastní .img
├── setup-build-machine.sh  # Příprava Ubuntu build stroje (jednorázově)
├── src/
│   └── modules/       # Moduly (start_chroot_script + files/)
│       ├── 01-kiosk-base/
│       ├── 02-vnc/
│       ├── 03-claude-code/
│       ├── 04-audio/
│       ├── 05-ha-bootstrap/
│       ├── 06-monitoring/
│       └── 07-keyboard/   # Volitelný (jen pro dotykové kiosky)
├── config/            # Konfigurace (šablony, bez citlivých dat)
├── ha-addon/          # HA Addon — Kiosk Builder UI
├── docs/              # Veškerá dokumentace
└── README.md
```

## Verze

| Komponenta | Verze |
|------------|-------|
| RPi OS Lite 64-bit | Bookworm (2024-11-19) |
| Chromium | latest apt |
| Node.js | 20.x LTS |
| RealVNC | latest apt |
| PipeWire | latest apt |

## Licence

MIT — volně použitelné, sdílitelné, bez citlivých dat.
