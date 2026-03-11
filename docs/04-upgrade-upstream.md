# Jak upgradovat upstream RPi OS

## Princip

Tvoje moduly jsou **zcela oddělené** od RPi OS.
Upgrade = změna URL/verze v config + rebuild.
Žádné merge konflikty, žádné patche.

---

## Postup upgradu

### 1. Zkontroluj novou verzi RPi OS

RPi OS vydání sleduj na:
- https://www.raspberrypi.com/software/operating-systems/
- https://github.com/raspberrypi/raspios_lite_arm64/releases

Hledáš: `YYYY-MM-DD-raspios-bookworm-arm64-lite.img.xz`

### 2. Aktualizuj CustomPiOS submodule

```bash
cd ha-kiosk-os
git submodule update --remote upstream/CustomPiOS
git add upstream/CustomPiOS
git commit -m "chore: update CustomPiOS submodule"
```

### 3. Změň verzi RPi OS v konfigu

```bash
nano config/build.conf
```

Aktualizuj:
```bash
# Stará verze
RPI_OS_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz"

# Nová verze (příklad)
RPI_OS_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2025-03-15/2025-03-15-raspios-bookworm-arm64-lite.img.xz"
```

### 4. Rebuild

```bash
git checkout dev
sudo ./build.sh
```

### 5. Testování

Před mergem do main:
- [ ] Flashni nový image na testovací SD kartu
- [ ] Ověř firstboot projde bez chyb
- [ ] Chromium se spustí na HA dashboard
- [ ] VNC přístup funguje
- [ ] SSH přístup funguje
- [ ] Claude Code funguje (`claude --version`)
- [ ] Audio funguje
- [ ] Watchdog funguje (kill chromium → restart do 15s)

### 6. Commit a tag

```bash
git add config/build.conf
git commit -m "chore: upgrade RPi OS na 2025-03-15"
git checkout main
git merge dev
git tag v1.1.0
git push origin main --tags
```

---

## Upgrade pouze CustomPiOS (bez nového RPi OS)

```bash
git submodule update --remote upstream/CustomPiOS
git add upstream/CustomPiOS
git commit -m "chore: update CustomPiOS"
```

---

## Kdy upgradovat?

| Situace | Doporučení |
|---------|-----------|
| Security patch RPi OS | Upgraduj do týdne |
| Nová feature RPi OS | Upgraduj při příležitosti |
| Stable release → nový major | Otestuj na dev větvi nejdřív |
| Moduly fungují, nic není rozbité | Není potřeba spěchat |

---

## Poznámky

- Bookworm (Debian 12) je aktuální základ — neupgraduj na Trixie dokud není stable
- Při přechodu na novou verzi Debianu (Bookworm→Trixie) ověř VŠECHNY moduly
- CustomPiOS submodule a RPi OS verze jsou na sobě nezávislé — můžeš upgradovat každé zvlášť
