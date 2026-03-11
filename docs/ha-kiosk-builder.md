# ha-kiosk-builder — Průvodce přípravou build stroje

Tento průvodce tě provede od nulového stavu (čerstvý Synology NAS s VMM)
až po první úspěšný build ha-kiosk-os image.

> **Proč Synology VMM místo GitHub Actions?**
> Build vyžaduje QEMU ARM64 emulaci přes chroot — na lokálním stroji
> s plným výkonem trvá 30–60 min. GitHub Actions by byl pomalý
> (sdílené runnery, emulace v emulaci) a drahý (artifacts ~3 GB).

---

## Přehled architektury build procesu

```
Synology NAS
└── VMM → Ubuntu 22.04 VM (4 CPU, 4 GB RAM, 40 GB disk)
    └── build.sh
        ├── Stáhne RPi OS Lite 64-bit image (.img.xz)
        ├── Rozbalí → připojí jako loop device
        ├── Zkopíruje qemu-aarch64-static do image
        ├── Pro každý modul (01–06):
        │   ├── Zkopíruje files/ → rootfs image
        │   └── Spustí start_chroot_script v ARM64 chrootu
        └── Umountuje → výsledný .img soubor
```

Výsledný soubor: `src/image/ha-kiosk-os-YYYY-MM-DD.img` (~3 GB)

---

## 1. Synology VMM — příprava VM

### Požadavky
- Synology NAS s balíčkem **Virtual Machine Manager** (DSM 7+)
- Doporučený hardware: DS923+, DS1522+, RS1221+ nebo novější (min. 8 GB RAM na NAS)
- Ubuntu Server 22.04 LTS ISO

### Stažení Ubuntu ISO

```
https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso
```

Velikost: ~2 GB

### Nahrání ISO do Synology VMM

1. Otevři **Virtual Machine Manager** → záložka **Image**
2. Klikni **Add** → **From Computer** → vyber stažené `.iso`
3. Počkej na nahrání (~5–10 min podle sítě)

### Vytvoření VM

1. VMM → **Virtual Machine** → **Create**
2. Zvol **Linux**
3. Název: `ha-kiosk-builder`
4. **CPU**: 4 jádra
5. **RAM**: 4 096 MB (4 GB)
6. **Disk**: 40 GB (Virtual Disk)
7. **Firmware**: **Legacy BIOS** ← důležité, UEFI může mít problémy v Synology VMM
8. **ISO**: vyber nahraný `ubuntu-22.04.5-live-server-amd64.iso`
9. Síť: výchozí (VirtIO nebo E1000)
10. Klikni **Create** → pak **Start**

---

## 2. Instalace Ubuntu Server 22.04

Klikni **Connect** v VMM pro otevření konzole.

### Průběh instalace

| Krok | Co zadat |
|------|----------|
| Jazyk | English |
| Klávesnice | Czech nebo English (US) |
| Typ instalace | Ubuntu Server (minimalized) |
| Síť | ponech výchozí (DHCP) |
| Proxy | prázdné, Enter |
| Mirror | potvrd výchozí |
| Storage | Use entire disk → Done → Continue |
| Uživatel | jméno: `roman`, server: `ha-kiosk-builder`, heslo: zvol si |
| SSH | ✅ **Install OpenSSH server** — zaškrtni! |
| Snaps | nic nevybirej, Continue |

Instalace trvá **5–10 minut**. Po dokončení klikni **Reboot Now**.

### Získání IP adresy

Po rebootu se přihlaš do konzole a zjisti IP:
```bash
ip addr show | grep "inet "
```

Od teď můžeš pracovat přes SSH z Windows:
```
ssh roman@192.168.1.XXX
```

---

## 3. Příprava build prostředí

### Automatická instalace (doporučeno)

Zkopíruj skript na server a spusť:

```bash
# Na build stroji (Ubuntu VM)
curl -fsSL https://raw.githubusercontent.com/romankysely/ha-kiosk-os/dev/setup-build-machine.sh \
  | sudo bash
```

Nebo manuálně:

```bash
# Stažení z repozitáře
git clone https://github.com/romankysely/ha-kiosk-os.git /tmp/setup
sudo bash /tmp/setup/setup-build-machine.sh
```

Skript nainstaluje všechny závislosti a ověří že QEMU ARM64 emulace funguje.

### Manuální instalace

Pokud chceš vědět co se instaluje:

```bash
sudo apt-get update && sudo apt-get upgrade -y

sudo apt-get install -y \
    git \
    curl \
    wget \
    xz-utils \
    p7zip-full \
    zip \
    unzip \
    jq \
    python3 \
    qemu-user-static \
    binfmt-support \
    parted \
    kpartx \
    util-linux \
    mount \
    e2fsprogs \
    fdisk

# Aktivuj binfmt pro ARM64
sudo systemctl restart systemd-binfmt

# Ověření
qemu-aarch64-static --version
sudo update-binfmts --display qemu-aarch64
```

Výstup `update-binfmts` musí obsahovat `enabled`.

---

## 4. Klonování repozitáře

```bash
# SSH klíč (volitelné, ale doporučené pro push)
ssh-keygen -t ed25519 -C "ha-kiosk-builder" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
# Zkopíruj veřejný klíč → GitHub → Settings → SSH Keys

# Klonování (HTTPS, bez SSH klíče)
git clone https://github.com/romankysely/ha-kiosk-os.git
cd ha-kiosk-os

# Přepni na dev větev
git checkout dev
```

---

## 5. Konfigurace buildu

```bash
nano config/build.conf
```

### Klíčové parametry

```bash
# URL ke stažení RPi OS image
# Aktuální verze: https://downloads.raspberrypi.com/raspios_lite_arm64/images/
RPI_OS_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/..."

# SHA256 checksum (stáhni z téže stránky, soubor *.img.xz.sha256)
RPI_OS_SHA256="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Název výsledného image
IMAGE_NAME="ha-kiosk-os"

# Přidat místo do image (GB) — moduly potřebují cca 3–4 GB navíc
EXTRA_SIZE_GB="4"

# Komprese výsledného image (false = rychlejší, true = menší soubor)
COMPRESS_IMAGE="false"
```

### Aktuální SHA256 a URL

Stáhni z oficálního zdroje:
```bash
# Zobraz dostupné verze
curl -s https://downloads.raspberrypi.com/raspios_lite_arm64/images/ | grep -o 'href="[^"]*/"' | tail -5

# Stáhni SHA256 pro konkrétní verzi (příklad)
curl -s https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz.sha256
```

---

## 6. Spuštění buildu

```bash
cd ~/ha-kiosk-os
sudo ./build.sh
```

### Typický průběh a výstupy

```
[ha-kiosk-os] === Build start ===
[ha-kiosk-os] Stahuji RPi OS image...
[ha-kiosk-os] SHA256 OK
[ha-kiosk-os] Rozbaluji image...
[ha-kiosk-os] Zvětšuji image o 4 GB...
[ha-kiosk-os] Mountuji image...
[ha-kiosk-os] --- Modul 01-kiosk-base ---
[01-kiosk-base] apt-get install xorg openbox chromium-browser...
...
[ha-kiosk-os] --- Modul 06-monitoring ---
[06-monitoring] pip3 install glances...
[ha-kiosk-os] Unmount a cleanup...
[ha-kiosk-os] === Build HOTOVO ===
[ha-kiosk-os] Image: src/image/ha-kiosk-os-2025-01-15.img
[ha-kiosk-os] Velikost: 3.2 GB
```

**Čas buildu:** 30–60 minut (závisí na rychlosti NAS a internetu)

### Volitelné parametry

```bash
# Přeskoč stahování (image je už stažená)
sudo ./build.sh --skip-download

# Zachovej pracovní adresář po buildu (pro debug)
sudo ./build.sh --keep-workspace

# Použij jen vybrané moduly
sudo ./build.sh --modules=01-kiosk-base,02-vnc
```

---

## 7. Kopírování image z NAS na Windows PC

### Varianta A — SCP (doporučeno)

Na Windows PC (PowerShell nebo WSL):

```powershell
scp roman@192.168.1.XXX:~/ha-kiosk-os/src/image/ha-kiosk-os-*.img C:\Users\roman\Downloads\
```

### Varianta B — Synology File Station

1. Otevři **File Station** v DSM
2. Naviguj na domovský adresář VM uživatele (přes SMB share nebo File Station)
3. Stáhni `.img` soubor do PC

### Varianta C — HTTP server (rychlé sdílení)

Na build stroji:
```bash
cd ~/ha-kiosk-os/src/image
python3 -m http.server 8888
```

Na Windows PC v prohlížeči: `http://192.168.1.XXX:8888`
→ klikni na `.img` soubor a stáhni

---

## 8. Flashování na SD kartu

Viz `docs/02-how-to-build.md` sekce **Flashování na SD kartu** —
postup s RPi Imager na Windows.

---

## 9. Troubleshooting

### Loop device zůstal připojený po chybě

```bash
# Zjisti připojené loop devices
sudo losetup -a

# Uvolni všechny
sudo losetup -D

# Uvolni mount pointy
sudo umount -R /tmp/kiosk-chroot 2>/dev/null || true
sudo rm -rf /tmp/kiosk-chroot
```

### QEMU chyba při chroot — "no such file or directory"

```bash
# Přeinstaluj qemu a restartuj binfmt
sudo apt-get install --reinstall qemu-user-static
sudo systemctl restart systemd-binfmt
sudo update-binfmts --enable qemu-aarch64

# Ověř
sudo update-binfmts --display qemu-aarch64
# Musí být: enabled
```

### DNS nefunguje v chrootu — apt-get nemůže rozbalit packety

```bash
# Zkontroluj resolv.conf v image (build.sh to kopíruje automaticky)
# Pokud stále selhává:
cat /etc/resolv.conf
# Musí obsahovat nameserver 8.8.8.8 nebo server tvého routeru
```

### "Permission denied" nebo "must be root"

```bash
sudo ./build.sh
# Build MUSÍ běžet jako root (loop devices, chroot, mount)
```

### Build selhal uprostřed — jak pokračovat

Build.sh při selhání vypíše číslo modulu. Spusť znovu s `--skip-download`
a pokud je workspace zachován (`--keep-workspace`), znovu mountuje stejnou image.

```bash
# Oprav modul, pak spusť znovu
sudo ./build.sh --skip-download
```

### Nedostatek místa na disku

```bash
df -h
# Build potřebuje: ~8 GB pro image + pracovní prostor
# Pokud VM disk nestačí, rozšiř ho v Synology VMM (Storage → resize)
```

---

## 10. Aktualizace na novou verzi RPi OS

1. Stáhni novou URL a SHA256 z `https://downloads.raspberrypi.com/raspios_lite_arm64/images/`
2. Aktualizuj `config/build.conf` — `RPI_OS_URL` a `RPI_OS_SHA256`
3. Commitni změnu
4. Spusť `sudo ./build.sh` (bez `--skip-download`)
