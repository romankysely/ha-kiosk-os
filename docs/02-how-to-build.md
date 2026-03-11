# Jak nasadit ha-kiosk-os

Existují tři přístupy — zvol podle počtu kiosků a dostupného vybavení.

| Přístup | Kiosků | Build stroj | Čas nasazení |
|---------|--------|-------------|--------------|
| A — Provisioning | 1-2 | Ne | ~30 min |
| B — Base image + firstboot | 3+ | Ano (Ubuntu VM) | ~5 min / kiosk |
| C — Offline image | 10+ | Ano (Ubuntu VM) | ~5 min / kiosk |

---

## Přístup A — Provisioning ⭐ (doporučeno pro začátek)

Flash stock RPi OS Lite → SSH → jeden příkaz. Žádný build stroj, žádný QEMU.
Moduly se instalují nativně na ARM64 hardware — jednoduché a spolehlivé.

### Krok 0 — Vytvoř HA uživatelský účet pro kiosk

**Každý kiosk se přihlašuje do HA pod svým uživatelským účtem.**
Účet určuje: přístupová práva, výchozí zobrazený dashboard.

1. HA → **Settings → People → Add Person**
2. Vyplň jméno (např. `Kiosk Obývák`) a přihlaš. jméno (např. `kiosk-obyvak`)
3. Pokud chceš aby kiosk zobrazoval specifický dashboard: nastav ho v HA pro tohoto uživatele
4. Přihlaš se do HA jako nový uživatel → klikni na jeho profil (vpravo nahoře) →
   scroll dolů → **Long-Lived Access Tokens → Create Token**
5. Zkopíruj token — vložíš ho do HA Addonu

### Krok 1 — Vygeneruj kiosk.conf v HA Addonu

- Otevři **Kiosk Builder Addon** v HA → klikni **Přidat kiosk**
- Vyplň: hostname, HA URL, HA username, token (z kroku 0), URL dashboardu
- Klikni **Uložit** → stáhni `kiosk.conf`

### Krok 2 — Flash stock RPi OS Lite 64-bit

Přes [RPi Imager](https://www.raspberrypi.com/software/):
- Device: **Raspberry Pi 5**
- OS: **Raspberry Pi OS Lite (64-bit)**
- Edit Settings:
  - `username=pi` ← **povinné**, moduly hardcodují `/home/pi/`
  - `SSH enabled` ← **povinné**, jinak se nedostaneš na RPi
  - `hostname=kiosk-XX` ← volitelné, firstboot.sh ho přepíše z kiosk.conf

**WiFi:**
- **LAN (doporučeno pro provisioning):** WiFi nevyplňuj, zapoj ethernet kabel
- **WiFi kiosk:** WiFi vyplnit v Imageru — provision.sh potřebuje internet ihned při startu
  (`KIOSK_NETWORK=wifi` v kiosk.conf pak WiFi zachová i po dokončení firstbootu)

### Krok 3 — Zkopíruj soubory na boot partition

Po flashování je boot partition viditelná ve Windows Průzkumníkovi jako USB disk.
Zkopíruj tyto soubory vedle ostatních souborů (cmdline.txt, config.txt...):

| Soubor | Zdroj | Popis |
|--------|-------|-------|
| `kiosk.conf` | stažen z HA Addonu (Krok 1) | Konfigurace kiosku |
| `kiosk-setup.sh` | z repozitáře (root) | Průvodce instalací — nabídne spuštění |

`kiosk-setup.sh` stáhneš z: `https://github.com/romankysely/ha-kiosk-os/blob/main/kiosk-setup.sh`
(klikni **Raw** → ulož jako `kiosk-setup.sh`)

### Krok 3b — Vlož SD kartu do RPi a zapni

1. Vysuň SD kartu z čtečky / počítače
2. Vlož ji do Raspberry Pi 5 (slot je na spodní straně desky)
3. Připoj ethernet kabel (doporučeno pro provisioning)
4. Připoj napájení (USB-C 27W) → RPi se automaticky spustí

Počkej ~30-60 sekund než RPi nabootuje a připojí se do sítě.

### Krok 4 — SSH do RPi a spusť průvodce instalací

```bash
ssh pi@kiosk-XX.local

bash /boot/firmware/kiosk-setup.sh
```

Průvodce zobrazí načtenou konfiguraci a zeptá se `[Y/n]`. Po potvrzení
sleduj průběh přímo v SSH okně:
- Číslované sekce `[1/7]` až `[7/7]` s časem od startu
- Průběh každého modulu `[1/6]`, `[2/6]` ...
- Závěrečný report se souhrnem

Pro sledování v druhém SSH okně:
```bash
tail -f /var/log/kiosk-provision.log
```

Po dokončení RPi automaticky **rebootuje** → kiosk je hotový (~20-40 min).
Výsledný report: `/var/log/kiosk-provision-report.txt`

### Co se stane při provisioning

```
provision.sh
├── Čeká na síť
├── apt-get update
├── git clone ha-kiosk-os repo → /opt/ha-kiosk-os
├── Pro každý modul (dle KIOSK_MODULES v kiosk.conf):
│   ├── cp -r files/ → /
│   └── bash start_chroot_script  (nativně na ARM64!)
├── bash firstboot.sh
│   ├── Nastaví hostname, síť
│   ├── Phone-home → HA Addon (dostane SSH klíč)
│   ├── Injektuje HA token do Chromia
│   └── Smaže kiosk.conf (bezpečnost)
└── reboot
```

### Výběr modulů

V `kiosk.conf` nastav `KIOSK_MODULES`:

```bash
# Standardní:
KIOSK_MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring"

# Minimální (jen kiosk + bootstrap):
KIOSK_MODULES="01-kiosk-base 05-ha-bootstrap"
```

### Troubleshooting provisioning

```bash
# Log
cat /var/log/kiosk-provision.log

# Opakované spuštění (pokud přerušeno)
sudo rm /etc/ha-kiosk-os_provisioned
sudo bash /opt/ha-kiosk-os/provision.sh

# Síť nefunguje
ip addr show
sudo systemctl restart networking
```

---

## Přístup B — Base image + firstboot ⭐⭐ (3+ kiosků)

Jednou postav "HA KioskOS Base" image se všemi moduly předinstalovanými.
Každý další kiosk pak nasadíš za ~5 min — jen flash + kiosk.conf + boot.

### Kdy použít

- Máš 3+ kiosků
- Chceš konzistentní prostředí (všechny kiosky identické)
- Chceš rychlé nasazení (objednáš nový Pi → za hodinu hotový kiosk)
- Máš Ubuntu VM (Synology VMM nebo jiný Linux)

### Příprava — Build base image (jednou)

```bash
# Na Ubuntu VM (build stroj):
git clone https://github.com/romankysely/ha-kiosk-os.git
cd ha-kiosk-os && git checkout dev

# Instalace závislostí (jednou):
sudo bash setup-build-machine.sh

# Build base image (30-60 min):
sudo bash build.sh
# Výsledek: src/image/ha-kiosk-os-YYYY-MM-DD.img
```

Tento image je **bez per-device konfigurace** (žádný token, žádný hostname).
Při prvním startu automaticky spustí `firstboot.sh` pokud najde `kiosk.conf`.

### Nasazení každého kiosku (opakovaně)

**1. Flash base image** přes [RPi Imager](https://www.raspberrypi.com/software/):
- Choose OS → **Use custom** → vyber `ha-kiosk-os-YYYY-MM-DD.img`
- Edit Settings: `username=pi`, `SSH enabled`

**2. Zkopíruj `kiosk.conf`** na boot partition (jako u Přístupu A)

**3. Vlož SD do RPi a zapni** — za ~5 min je kiosk hotový automaticky:
```
Boot → kiosk-firstboot.service detekuje kiosk.conf
     → firstboot.sh: hostname, síť, phone-home, HA token, reboot
     → Chromium → HA dashboard ✓
```
Log: `/var/log/kiosk-firstboot.log`

### Kdy obnovit base image

- Při vydání bezpečnostní aktualizace RPi OS
- Při změně modulů (přidání/odebrání)
- Přibližně každé 3-6 měsíců pro čerstvé balíčky

```bash
# Obnova image na build stroji:
git pull origin dev     # aktualizuj moduly
sudo bash build.sh      # nový build (~30-60 min)
# Distribuuj nový .img na všechna RPi (při dalším flashování)
```

---

## Přístup C — Offline image (záloha, 10+ kiosků)

Stejný image jako Přístup B, ale distribuce probíhá offline (USB disk, SD karta, síťový share).
Vhodné pro: nasazení bez internetu na místě, velký počet kiosků, garantované verze.

Vyžaduje Linux build stroj (Ubuntu 22.04 VM na Synology VMM).
**Viz podrobný průvodce [`docs/ha-kiosk-builder.md`](ha-kiosk-builder.md)**

### Požadavky na build stroj

```bash
sudo apt-get install -y \
    git curl wget xz-utils p7zip-full zip unzip jq python3 \
    qemu-user-static binfmt-support \
    parted kpartx util-linux mount e2fsprogs fdisk

# Nebo automaticky:
sudo bash setup-build-machine.sh
```

### Spuštění buildu

```bash
git clone https://github.com/romankysely/ha-kiosk-os.git
cd ha-kiosk-os && git checkout dev
sudo bash build.sh                          # plný build
sudo bash build.sh --modules=01-kiosk-base  # testovací build
```

Build trvá **30–60 minut**. Výsledný image: `src/image/ha-kiosk-os-YYYY-MM-DD.img`

### Flashování image

1. Stáhni [RPi Imager](https://www.raspberrypi.com/software/)
2. Choose OS → Use custom → vyber `.img` soubor
3. Edit Settings: `username=pi`, `SSH enabled`, `hostname`
4. Po flashování zkopíruj `kiosk.conf` na boot partition

### Co se stane při prvním startu (Přístup B a C)

```
Boot → kiosk-firstboot.service detekuje kiosk.conf
     → firstboot.sh: hostname, síť, phone-home, HA token, reboot
     → Chromium kiosk mode
```

Log: `/var/log/kiosk-firstboot.log`

### Troubleshooting image buildu

```bash
# Uvolni zaseknuté loop devices
sudo losetup -D && sudo umount -R /tmp/kiosk-chroot 2>/dev/null || true

# Opakuj build bez stahování
sudo bash build.sh --skip-download

# qemu chyba
sudo apt-get install --reinstall qemu-user-static
sudo systemctl restart systemd-binfmt
```

---

## Průběžná údržba kiosků

Jednou za čas stačí SSH přihlášení — **žádné reflashování, žádný build stroj**.

### Bezpečnostní aktualizace OS (jednou za 1-3 měsíce)

```bash
ssh pi@kiosk-obyvak.local

sudo apt update && sudo apt upgrade -y && sudo reboot
```

Aktualizuje: kernel, Chromium, systemd, a všechny ostatní systémové balíčky.
RPi se restartuje a kiosk pokračuje normálně.

### Aktualizace modulů (pokud změníš kód v repo)

Pokud jsi upravil soubory modulu v repozitáři (start_chroot_script nebo files/):

```bash
ssh pi@kiosk-obyvak.local

# Stáhni novou verzi repozitáře
cd /opt/ha-kiosk-os && sudo git pull

# Přehraj konkrétní modul
sudo bash src/modules/02-vnc/start_chroot_script

# Nebo jen překopíruj konfigurační soubory (bez reinstalace)
sudo cp -r src/modules/02-vnc/files/. /
sudo systemctl restart vnc   # pokud je potřeba restart služby
```

### Co kdy dělat

| Situace | Řešení |
|---------|--------|
| Bezpečnostní záplata OS | `apt upgrade` přes SSH |
| Změna konfigurace modulu | `git pull` + překopírovat `files/` |
| Změna install logiky modulu | `git pull` + spustit `start_chroot_script` |
| Nový modul, velká změna | Reprovisioning (`provision.sh`) |
| Nová verze RPi OS | Reflash (jednou ročně) |
