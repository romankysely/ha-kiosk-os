# HA KioskOS — kontext pro Claude Code

Tento soubor se čte automaticky při každém spuštění `claude` v tomto repozitáři.

---

## Co projekt dělá

Vlastní 64-bit RPi OS distribuce pro Raspberry Pi 5 kiosky zobrazující Home Assistant dashboardy.
Nasazuje se přes provisioning: flash stock RPi OS Lite → SSH → `sudo bash provision.sh`.
Záloha: `build.sh` na Ubuntu 22.04 VM (Synology VMM) — x86 host + QEMU ARM64 chroot.

**GitHub:** https://github.com/romankysely/ha-kiosk-os (privátní)
**Větev pro vývoj:** `dev`

---

## Architektura (3 vrstvy)

```
1. NASAZENÍ — 3 přístupy:

   A) PROVISIONING (provision.sh) ← PRO 1-2 KIOSKY, BEZ BUILD STROJE
      Flash stock RPi OS Lite → SSH → sudo bash provision.sh
      → klonuje repo → instaluje moduly nativně na ARM64 (~30 min)
      → firstboot konfigurace → reboot → hotový kiosk

   B) BASE IMAGE + FIRSTBOOT ← PRO 3+ KIOSKŮ, DOPORUČENO PRO PRODUKCI
      1× build.sh na Ubuntu VM → ha-kiosk-os-base.img (předinstalované moduly)
      Flash base image → přidej kiosk.conf → boot → firstboot.sh (~5 min) ✓

   C) OFFLINE IMAGE ← PRO 10+ KIOSKŮ BEZ INTERNETU
      Jako B, ale image se distribuje offline

2. MODULY (src/modules/01-06)
   Každý modul = start_chroot_script + files/ (struktura odpovídá rootfs /)
   Fungují jak při provisioning (nativně na RPi) tak při image buildu (QEMU chroot)
   Výběr modulů: KIOSK_MODULES v kiosk.conf

3. HA ADDON (ha-addon/)
   Flask webová aplikace běžící v Home Assistant jako addon
   Spravuje kiosky: generuje kiosk.conf, přijímá phone-home registrace,
   poskytuje SSH veřejný klíč novým kioskům
   Nově: ukládá HA username a dashboard URL z každého kiosku
```

## HA uživatelský účet pro kiosk

Každý kiosk se přihlašuje do HA pod dedikovaným uživatelským účtem.
- Účet určuje: přístupová práva, výchozí dashboard
- kiosk.conf obsahuje: `KIOSK_HA_USERNAME` a `KIOSK_HA_TOKEN` (LLAT pro tohoto uživatele)
- Token vytvoří správce v HA profilu uživatele (Long-Lived Access Token)
- **Nikdy** nepoužívej admin účet pro kiosky — vždy dedikovaný uživatel s omezenými právy

---

## Aktuální stav — co je hotové ✅

| Komponenta | Stav | Poznámka |
|------------|------|----------|
| `src/modules/01-kiosk-base` | ✅ hotovo | xorg, openbox, chromium, watchdog, autologin |
| `src/modules/02-vnc` | ✅ hotovo | RealVNC Server, SystemAuth, port 5900 |
| `src/modules/03-claude-code` | ✅ hotovo | Node.js 20 + Claude Code přes npm |
| `src/modules/04-audio` | ✅ hotovo | PipeWire + snapclient, placeholder __SNAPCAST_HOST__ |
| `src/modules/05-ha-bootstrap` | ✅ hotovo | firstboot.sh, inject-ha-token.py, phone-home |
| `src/modules/06-monitoring` | ✅ hotovo | Glances web UI port 61208 |
| `build.sh` | ✅ hotovo | loop device, chroot, resize +4GB, SHA256 verify |
| `ha-addon/` | ✅ hotovo | Flask UI, /api/register, kiosk správa |
| `config/kiosk.conf.template` | ✅ hotovo | šablona bez citlivých dat |
| `setup-build-machine.sh` | ✅ hotovo | jednorázová příprava Ubuntu VM |
| `docs/ha-kiosk-builder.md` | ✅ hotovo | průvodce Synology VMM |

**Co zbývá:**
- [ ] Otestovat provision.sh na fyzickém RPi 5
- [ ] Nainstalovat a otestovat HA Addon
- [ ] GitHub Actions workflow (low priority)

---

## Klíčová technická rozhodnutí

### Proč vlastní build.sh místo hotového build systému
`build.sh` implementuje jednoduchý vzor (loop device + qemu-aarch64-static chroot) bez externích závislostí.
Alternativně (a primárně): provisioning nativně přímo na ARM64 hardware — bez QEMU, jednodušší.

### Claude Code přes npm, ne native installer
Native installer má bug na aarch64 — chybí binárky pro ARM64.
Řešení: `npm install -g @anthropic-ai/claude-code` v chroot s prefix `~/.npm-global`.

### HA token injection přes Chromium extension
LevelDB Python přístup je nespolehlivý (binární formát, zamykání).
Řešení: Manifest V3 extension v `~/.config/chromium/ha_token_injector/` která
při `document_start` spustí `localStorage.setItem('hassTokens', ...)`.

### Phone-home přes dedikovaný port
HA API nepřeposílá addon routes přímo. HA Addon naslouchá na portu 8099.
`KIOSK_ADDON_URL` v kiosk.conf říká RPi kam volat.

### Placeholdery v image
`__DASHBOARD_URL__` a `__SNAPCAST_HOST__` jsou v souborech image.
`firstboot.sh` je nahradí hodnotami z `kiosk.conf` při prvním startu.

---

## Struktura repozitáře

```
ha-kiosk-os/
├── CLAUDE.md                    ← tento soubor
├── CLAUDE_CODE_HANDOFF.md       ← historický kontext z prvního chatu
├── build.sh                     ← hlavní build skript (spusť jako root)
├── setup-build-machine.sh       ← příprava Ubuntu build stroje
├── config/
│   ├── build.conf               ← URL, SHA256, parametry buildu ← AKTUALIZUJ SHA256!
│   └── kiosk.conf.template      ← šablona kiosk.conf (bez hesel)
├── src/modules/
│   ├── 01-kiosk-base/           ← Chromium kiosk, openbox, autologin, watchdog
│   ├── 02-vnc/                  ← RealVNC Server
│   ├── 03-claude-code/          ← Node.js 20 + Claude Code CLI
│   ├── 04-audio/                ← PipeWire + Snapcast client
│   ├── 05-ha-bootstrap/         ← firstboot.sh, HA token injection, phone-home
│   └── 06-monitoring/           ← Glances monitoring web UI

├── ha-addon/                    ← Home Assistant Addon "Kiosk Builder"
│   ├── config.yaml
│   ├── Dockerfile
│   ├── run.sh
│   └── app/                     ← Flask aplikace (main.py, templates/, static/)
└── docs/
    ├── 00-overview.md
    ├── 02-how-to-build.md
    ├── ha-kiosk-builder.md      ← průvodce přípravou Synology VMM build stroje
    └── modules/                 ← dokumentace každého modulu
```

---

## Jak nasadit kiosk (provisioning přístup — doporučeno)

```bash
# 1. Flash stock RPi OS Lite 64-bit přes RPi Imager
#    → nastav: user=pi, SSH enabled, hostname

# 2. Na boot partition zkopíruj kiosk.conf (vygenerovaný HA Addonem)

# 3. SSH do RPi a spusť provision.sh
curl -fsSL https://raw.githubusercontent.com/romankysely/ha-kiosk-os/dev/provision.sh | sudo bash

# Nebo pokud jsi zkopíroval provision.sh na boot partition:
sudo bash /boot/firmware/provision.sh

# 4. Sleduj log
tail -f /var/log/kiosk-provision.log
```

## Záloha: image build (Ubuntu VM + QEMU)

```bash
# Jen pokud potřebuješ offline nasazení nebo 10+ kiosků
cd ~/ha-kiosk-os
sudo bash build.sh --modules=01-kiosk-base  # testovací build
sudo bash build.sh                           # plný build
```

---

## Git workflow

```bash
git checkout dev          # vždy pracuj na dev
git add <soubory>
git commit -m "typ: popis"
git push origin dev

# Commit typy: feat / fix / docs / chore
```

---

## Bezpečnostní pravidla — VŽDY dodržuj

- **Nikdy** necommituj: tokeny, hesla, IP adresy, SSH klíče, kiosk.conf
- Šablony používají placeholdery: `YOUR_HA_URL`, `YOUR_TOKEN`, `__DASHBOARD_URL__`
- `ha-addon/app/data/` je v `.gitignore` (runtime data addonu)
- Po push vždy odstraň PAT token z git remote URL

---

## Hardware cíl

- **Raspberry Pi 5** — aarch64 (64-bit ARM)
- 4 GB RAM minimum
- RPi OS Bookworm Lite 64-bit jako základ
- Síť: primárně LAN (WiFi volitelně přes kiosk.conf)
