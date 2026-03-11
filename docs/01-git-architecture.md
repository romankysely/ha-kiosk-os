# Git architektura

## Princip

Jeden veřejný repozitář obsahuje vše. Základ je stock RPi OS Lite (není v repo),
tvoje práce jsou moduly v `src/modules/`.

```
github.com/romankysely/ha-kiosk-os  (veřejný repo)
│
└── src/modules/           ← TVOJE práce, zde tvoříš a měníš
    ├── 01-kiosk-base/
    ├── 02-vnc/
    ...
```

---

## Struktura repozitáře

```
ha-kiosk-os/
│
├── .gitignore             # Co NIKDY nejde do gitu (citlivé soubory!)
├── README.md
├── CLAUDE.md              # Kontext pro Claude Code (čte se automaticky)
├── provision.sh           # Primární nasazení: stock RPi OS → kiosk
├── build.sh               # Záloha: Ubuntu VM + QEMU → vlastní .img
├── setup-build-machine.sh # Příprava Ubuntu build stroje
│
├── src/
│   └── modules/
│       ├── 01-kiosk-base/
│       │   ├── start_chroot_script   # Bash skript spuštěný při instalaci
│       │   ├── files/                # Soubory kopírované do rootfs /
│       │   │   ├── etc/
│       │   │   ├── home/pi/
│       │   │   └── usr/local/bin/
│       │   └── README.md
│       ├── 02-vnc/
│       ├── 03-claude-code/
│       ├── 04-audio/
│       ├── 05-ha-bootstrap/
│       └── 06-monitoring/
│
├── config/
│   ├── build.conf             # Verze RPi OS, parametry buildu
│   └── kiosk.conf.template    # Šablona config souboru (bez citlivých dat!)
│
├── ha-addon/                  # HA Addon — Kiosk Builder
│   ├── config.yaml
│   ├── Dockerfile
│   ├── run.sh
│   └── app/
│       ├── main.py
│       └── templates/
│
└── docs/
    ├── 00-overview.md
    ├── 01-git-architecture.md    ← tento soubor
    ├── 02-how-to-build.md
    ├── 03-adding-module.md
    ├── 04-upgrade-upstream.md
    ├── 05-ha-addon.md
    ├── 06-security.md
    ├── ha-kiosk-builder.md
    └── modules/
        ├── kiosk-base.md
        ├── vnc.md
        ├── claude-code.md
        ├── audio.md
        ├── ha-bootstrap.md
        └── monitoring.md
```

---

## Branches

```
main     ← stabilní, ověřená verze
          → každý commit = funkční image
          → taguj verzemi: v1.0.0, v1.1.0 ...

dev      ← vývoj, testování nových modulů
          → merge do main až po ověření

feature/nazev-funkce  ← konkrétní nová funkce
          → větví se z dev
          → merge do dev po dokončení
```

### Kdy použít který branch

| Situace | Branch |
|---------|--------|
| Přidávám nový modul | feature/nazev → dev → main |
| Opravuji bug | dev → main |
| Upgraduju RPi OS | dev → main |
| Produkční kiosky | vždy main |

---

## Denní workflow

### Přidání nové funkce

```bash
# 1. Přepni na dev
git checkout dev
git pull

# 2. Vytvoř feature branch
git checkout -b feature/nova-funkce

# 3. Pracuj...
# ... edituj src/modules/ ...

# 4. Commitni
git add .
git commit -m "feat: přidán modul pro xyz"

# 5. Merge do dev
git checkout dev
git merge feature/nova-funkce
git branch -d feature/nova-funkce

# 6. Po otestování merge do main
git checkout main
git merge dev
git tag v1.2.0
git push origin main --tags
```

### Oprava bugu

```bash
git checkout dev
# ... oprav ...
git commit -m "fix: popis opravy"
git checkout main
git merge dev
git push
```

---

## Co NIKDY nejde do gitu (.gitignore)

```gitignore
# Citlivé soubory generované za běhu
config/kiosk.conf
config/kiosk-*.conf
*.conf.local

# SSH klíče
*.pem
id_rsa
id_ed25519
*.key

# Build artefakty
*.img
*.img.xz
*.zip
src/image/
workspace/

# HA Addon data
ha-addon/app/data/
ha-addon/data/

# Python
__pycache__/
*.pyc
.env

# Systémové
.DS_Store
*.log
```

---

## Jak naklonovat repo na novém stroji

```bash
git clone https://github.com/romankysely/ha-kiosk-os.git
cd ha-kiosk-os
git checkout dev
```

---

## Commit message konvence

```
feat: přidána nová funkce
fix: oprava bugu
docs: aktualizace dokumentace
chore: upgrade závislostí, build věci
refactor: přepsání bez změny funkce
```

Příklady:
```
feat: modul 04-audio — přidán Snapcast klient
fix: 01-kiosk-base — oprava HW video dekódování na Pi5
docs: 02-how-to-build — doplněn postup pro Windows
chore: upgrade RPi OS na 2025-03-15
```
