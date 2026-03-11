# HA KioskOS

Specializovaná 64-bit RPi distribuce pro Home Assistant kiosky.
Náhrada za FullpageOS — modernější, 64-bit, s plnou podporou Claude Code.

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

## Rychlý start

Viz [docs/02-how-to-build.md](docs/02-how-to-build.md)

```
1. Naklonuj repo
2. Nastav config/build.conf
3. ./build.sh → vygeneruje .img
4. Flashni přes RPi Imager (vlastní image)
5. Na SD kartu zkopíruj kiosk.conf (generovaný z HA Addonu)
6. SD → RPi → zapni → hotovo
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
├── upstream/          # Git submodule — CustomPiOS (nikdy neupravuj)
├── src/
│   └── modules/       # Tvoje moduly
│       ├── 01-kiosk-base/
│       ├── 02-vnc/
│       ├── 03-claude-code/
│       ├── 04-audio/
│       ├── 05-ha-bootstrap/
│       └── 06-monitoring/
├── config/            # Konfigurace buildu (šablony, bez citlivých dat)
├── ha-addon/          # HA Addon — Kiosk Builder UI
├── docs/              # Veškerá dokumentace
├── build.sh           # Hlavní build skript
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
