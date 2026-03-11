# HA KioskOS — Handoff dokument pro Claude Code

> **Poznámka:** Tento dokument je historický kontext z prvního chatu.
> Pro aktuální stav projektu viz **`CLAUDE.md`** — ten se čte automaticky.

---

## Kontext projektu

Roman provozuje Home Assistant na Synology RS1619xs+ (Intel Xeon D-1527) přes VMM.
Má RPi5 kiosky zobrazující HA dashboardy. Dosud používal FullpageOS (32-bit armhf)
který nahrazujeme vlastní 64-bit distribucí.

**Hlavní důvody přechodu z FullpageOS:**
- FullpageOS je 32-bit (armhf) → nelze nainstalovat Claude Code
- FullpageOS je prakticky neudržovaný projekt
- x11vnc nahrazujeme RealVNC (rychlejší, stabilnější)
- Chceme plnou kontrolu nad image a moduly

---

## Repozitář

Název: `ha-kiosk-os` (privátní GitHub repo: https://github.com/romankysely/ha-kiosk-os)

### Git workflow
- `main` — stabilní, produkční
- `dev` — vývoj (zde pracujeme)
- `feature/xxx` — nové funkce (větví z dev)

### Klonování
```bash
git clone https://github.com/romankysely/ha-kiosk-os.git
cd ha-kiosk-os
git checkout dev
```

---

## Aktuální stav projektu (vše hotovo ✅)

### Moduly (src/modules/)

Všech 6 modulů je plně implementováno — `start_chroot_script` + `files/`:

| Modul | Co dělá |
|-------|---------|
| `01-kiosk-base` | xorg, openbox, chromium kiosk, autologin TTY1, watchdog, HW video |
| `02-vnc` | RealVNC Server, SystemAuth, TLS, port 5900 |
| `03-claude-code` | Node.js 20 přes NodeSource, Claude Code přes npm (ne native — aarch64 bug) |
| `04-audio` | PipeWire + pipewire-pulse + wireplumber + snapclient |
| `05-ha-bootstrap` | firstboot.sh (10 kroků), inject-ha-token.py (Chromium extension), phone-home |
| `06-monitoring` | Glances přes pip3, web UI port 61208 |

### build.sh
Plně přepsán a opraven. Klíčové opravy:
- `xz --decompress --keep --stdout > file` (ne `-o` flag který neexistuje)
- Kopírování `/etc/resolv.conf` do chroot (DNS pro apt-get)
- `/dev/pts` a `/dev/shm` bind mounty
- Vyčištění `ld.so.preload` v chroot (ARM binary crash na x86 hostu)
- Resize image o +EXTRA_SIZE_GB GB (rootfs nestačila)
- SHA256 verifikace staženého image

### HA Addon (ha-addon/)
Flask webová aplikace s:
- Dashboard kiosků (online/offline status)
- Formulář pro přidání kiosku + generování kiosk.conf
- Detail kiosku + stažení kiosk.conf
- Průvodce instalací (wizard, 6 kroků)
- `/api/register` — phone-home endpoint (vrací SSH veřejný klíč)
- Port 8099, HA ingress, hassio_api: true

### Build stroj
Ubuntu 22.04 LTS VM na Synology VMM:
- `setup-build-machine.sh` — jednorázová instalace závislostí
- `docs/ha-kiosk-builder.md` — kompletní průvodce

---

## Hardwarové specifika

### Raspberry Pi 5
- **aarch64** (64-bit ARM) — cílová architektura
- `usb_max_current_enable=1` v config.txt — NUTNÉ pro napájení monitoru přes USB-A
- Dedikovaný HW video dekodér — V4L2, H.264/HEVC
- 4GB RAM (min. pro kiosk s Claude Code)

### Síť
- Primárně **LAN kabel** (jednodušší, spolehlivější)
- Volitelně WiFi (konfigurace přes kiosk.conf)
- HA server: `192.168.1.100:8123`

---

## Klíčová technická rozhodnutí

### Claude Code přes npm
Native installer má bug na aarch64 — chybí binárky.
`npm install -g @anthropic-ai/claude-code` s prefix `~/.npm-global` funguje.

### HA token injection přes Chromium extension
LevelDB Python přístup nespolehlivý. Manifest V3 extension:
- `~/.config/chromium/ha_token_injector/manifest.json`
- `inject.js` → `localStorage.setItem('hassTokens', ...)` při `document_start`
- `chromium-kiosk` spouštěn s `--load-extension` flagou

### Custom chroot místo CustomPiOS
CustomPiOS submodule není inicializovaný. Vlastní implementace v `build.sh`
dělá totéž (loop device + qemu-aarch64-static + chroot) bez závislosti.

### Phone-home přes dedikovaný port
HA Addon naslouchá na portu 8099 (ne přes HA API).
`KIOSK_ADDON_URL` v kiosk.conf.

---

## Bezpečnostní pravidla

1. **Nikdy** necommituj: tokeny, hesla, IP adresy, SSH klíče, kiosk.conf
2. `kiosk.conf` je vždy v `.gitignore`
3. SSH klíče jsou vždy v `.gitignore`
4. Šablony obsahují pouze placeholdery
5. `ha-addon/app/data/` je vždy v `.gitignore`

---

## Co zbývá

- [ ] Spustit první build a opravit případné chyby
- [ ] Aktualizovat SHA256 v `config/build.conf` na aktuální RPi OS verzi
- [ ] Otestovat na fyzickém RPi 5
- [ ] GitHub Actions workflow (low priority)
