# Přehled projektu HA KioskOS

## Co projekt řeší

HA KioskOS je 64-bit RPi distribuce pro Home Assistant kiosky, která řeší:
- Automatické přihlášení do HA dashboardu (Chromium kiosk mód + token injection)
- Vzdálený přístup bez fyzické přítomnosti (VNC, SSH, Claude Code)
- Multi-room audio z HA (PipeWire + Snapcast)
- Centrální správu kiosků přes HA Addon (provisioning, monitoring)
- HW video dekódování pro WebRTC kamery na Pi5

Postavena na čistém **RPi OS Lite 64-bit** rozšířeném o modulárně instalovatelné komponenty.

---

## Architektura celého systému

```
┌─────────────────────────────────────────────────────┐
│  Home Assistant (Synology VMM)                      │
│                                                     │
│  ┌──────────────────────────────┐                   │
│  │  HA Addon: Kiosk Builder     │                   │
│  │  - Správa kiosků (seznam)    │                   │
│  │  - Generování kiosk.conf     │                   │
│  │  - Průvodce instalací        │                   │
│  │  - Phone-home registrace     │                   │
│  │  - Monitoring kiosků         │                   │
│  └──────────────────────────────┘                   │
└───────────────────┬─────────────────────────────────┘
                    │ LAN
        ┌───────────┴───────────┐
        │                       │
┌───────▼────────┐    ┌─────────▼──────┐
│  Kiosk 1       │    │  Kiosk 2       │
│  RPi5          │    │  RPi5          │
│  ha-kiosk-os   │    │  ha-kiosk-os   │
│  192.168.1.101  │    │  192.168.1.102  │
└────────────────┘    └────────────────┘
```

---

## Jak se nasazuje

### Primární přístup: Provisioning (doporučeno)

```
Flash stock RPi OS Lite 64-bit (RPi Imager)
    +
kiosk.conf na boot partition (vygenerovaný HA Addonem)
    +
sudo bash provision.sh (klonuje repo + instaluje moduly nativně)
    =
Hotový kiosk po rebootu (~20-40 min)
```

### Záloha: Image build (Ubuntu VM + QEMU)

```
RPi OS Lite 64-bit (upstream, nezměněný)
    +
build.sh (Ubuntu VM, QEMU ARM64 chroot)
    +
Tvoje moduly (src/modules/)
    =
ha-kiosk-os-YYYY-MM-DD.img
```

Při vydání nové verze RPi OS:
1. Změníš číslo verze v `config/build.conf`
2. Spustíš `sudo bash build.sh`
3. Tvoje moduly se **nezměnily**, jen základ je novější

---

## Životní cyklus kiosku

```
FÁZE 1: Build image (jednou, nebo po upgradu OS)
  → vývojář spustí build.sh na Linux stroji
  → vznikne ha-kiosk-os.img

FÁZE 2: Příprava SD karty (pro každý nový kiosk)
  → uživatel stáhne ha-kiosk-os.img
  → flashne přes RPi Imager
  → z HA Addonu stáhne kiosk.conf
  → zkopíruje kiosk.conf na boot oddíl SD karty

FÁZE 3: Prvotní start (automatický)
  → RPi se zapne
  → firstboot.sh přečte kiosk.conf
  → zaregistruje se do HA Addonu (phone-home)
  → HA Addon potvrdí registraci, pošle SSH klíč
  → RPi restartuje → Chromium → HA dashboard

FÁZE 4: Provoz
  → Chromium kiosk mód, watchdog hlídá
  → VNC/SSH pro vzdálenou správu
  → HA Addon zobrazuje status kiosku
  → Claude Code dostupný přes SSH pro vzdálené úpravy
```

---

## Moduly — přehled

| Modul | Co dělá | Dokumentace |
|-------|---------|-------------|
| 01-kiosk-base | Chromium, Openbox, autologin, HW video | [kiosk-base.md](modules/kiosk-base.md) |
| 02-vnc | RealVNC server, vzdálený přístup | [vnc.md](modules/vnc.md) |
| 03-claude-code | Node.js 20, Claude Code CLI | [claude-code.md](modules/claude-code.md) |
| 04-audio | PipeWire, Snapcast klient, TTS | [audio.md](modules/audio.md) |
| 05-ha-bootstrap | Phone-home, firstboot registrace | [ha-bootstrap.md](modules/ha-bootstrap.md) |
| 06-monitoring | Glances, watchdog service | [monitoring.md](modules/monitoring.md) |
