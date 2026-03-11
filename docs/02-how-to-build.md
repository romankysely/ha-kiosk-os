# Jak nasadit ha-kiosk-os

Existují dva přístupy. **Provisioning je doporučený** pro domácí použití.

---

## Přístup 1 — Provisioning (doporučeno) ⭐

Flash stock RPi OS Lite → SSH → jeden příkaz. Žádný build stroj, žádný QEMU.
Moduly se instalují nativně na ARM64 hardware → rychlejší, jednodušší.

### Postup

**1. Flash stock RPi OS Lite 64-bit** přes [RPi Imager](https://www.raspberrypi.com/software/)
- Device: Raspberry Pi 5
- OS: Raspberry Pi OS Lite (64-bit)
- Edit Settings: `username=pi`, `SSH enabled`, `hostname=kiosk-XX`
- **WiFi NEVYPLŇUJ** — řeší se přes kiosk.conf

**2. Zkopíruj `kiosk.conf`** na boot partition (vygeneruj v HA Addonu)

Po flashování je boot partition viditelná ve Windows Průzkumníkovi jako USB disk.
Zkopíruj `kiosk.conf` vedle ostatních souborů (cmdline.txt, config.txt...).

**3. SSH do RPi** a spusť provisioning:

```bash
ssh pi@kiosk-XX.local

# Varianta A — přímý curl (nejjednodušší)
curl -fsSL https://raw.githubusercontent.com/romankysely/ha-kiosk-os/dev/provision.sh | sudo bash

# Varianta B — pokud jsi zkopíroval provision.sh na boot partition
sudo bash /boot/firmware/provision.sh
```

**4. Sleduj průběh** (volitelně v druhém SSH terminálu):

```bash
tail -f /var/log/kiosk-provision.log
```

**5.** Po dokončení RPi automaticky **rebootuje** → kiosk je hotový (~20-40 min).

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
# Standardní (bez dotykové klávesnice):
KIOSK_MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring"

# S dotykovou klávesnicí:
KIOSK_MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring 07-keyboard"

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

## Přístup 2 — Image build (záloha)

Vytvoří vlastní `.img` soubor. Vhodné pro:
- Offline nasazení (bez internetu na místě)
- 10+ kiosků (flash z jednoho obrazu)
- Garantované verze balíčků

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

### Co se stane při prvním startu (image přístup)

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
