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

## Jak se nasazuje — tři přístupy

### Přístup A: Provisioning ⭐ (1-2 kiosky, žádný build stroj)

```
Flash stock RPi OS Lite 64-bit (RPi Imager)
    + kiosk.conf na boot partition (vygenerovaný HA Addonem)
    + sudo bash provision.sh   ← klonuje repo, instaluje moduly nativně na ARM64
    = Hotový kiosk (~20-40 min, z toho většinu čas apt-get)
```

**Výhody:** Nevyžaduje build stroj, vždy aktuální balíčky.
**Vhodné pro:** První kiosk, testování, ojedinělá nasazení.

---

### Přístup B: Base image + firstboot ⭐⭐ (3+ kiosků, opakované nasazení)

```
1. JEDNOU: build.sh na Ubuntu VM → ha-kiosk-os-base.img (30-60 min)
   (image má všechny moduly předinstalované, žádná device-specific konfigurace)

2. PRO KAŽDÝ KIOSK:
   Flash ha-kiosk-os-base.img (RPi Imager)
    + kiosk.conf na boot partition
    = Boot → firstboot.sh se spustí automaticky (~5 min)
    = Chromium → HA dashboard ✓
```

**Výhody:** Nasazení každého dalšího kiosku trvá jen ~5 min místo 20-40 min.
**Vhodné pro:** Více kiosků, konzistentní prostředí, produkce.
**Base image se obnovuje:** Při vydání nové verze RPi OS nebo aktualizaci modulů.

---

### Přístup C: Vlastní image (offline nasazení, 10+ kiosků)

```
build.sh → ha-kiosk-os.img → flash → kiosk.conf → boot
```

Jako Přístup B, ale image se distribuje offline (USB disk, SD karta).

---

### Srovnání přístupů

| | A: Provisioning | B: Base image | C: Offline image |
|---|---|---|---|
| Build stroj | Ne | Ano (Ubuntu VM) | Ano (Ubuntu VM) |
| Čas nasazení | ~30 min | ~5 min | ~5 min |
| Počet kiosků | 1-2 | 3+ | 10+ |
| Vždy aktuální | Ano | Ne (jen při nové buildu) | Ne |
| Doporučeno pro | Začátečníky, testování | Produkci | Bez internetu |

---

## Životní cyklus kiosku (Přístup A — Provisioning)

```
KROK 1: Příprava (v HA Addonu)
  → Vytvoř HA uživatele pro kiosk (Settings → People → Add Person)
  → V HA Addonu: "Přidat kiosk" → vyplň hostname, HA URL, HA username, token, dashboard
  → Stáhni kiosk.conf

KROK 2: Příprava SD karty
  → Flash stock RPi OS Lite 64-bit přes RPi Imager (user=pi, SSH=on, hostname)
  → Zkopíruj kiosk.conf na boot partition SD karty (jako kiosk.conf)

KROK 3: Provisioning (automatický po SSH)
  → SSH do RPi → sudo bash provision.sh
  → Sleduj průběh na obrazovce (20-40 min)
  → Závěrečný report v /var/log/kiosk-provision-report.txt

KROK 4: Prvotní start (automatický)
  → firstboot.sh nakonfiguruje hostname, síť, dashboard URL
  → RPi se zaregistruje do HA Addonu (phone-home) → dostane SSH klíč
  → kiosk.conf se smaže (bezpečnost — obsahuje token)
  → RPi restartuje → Chromium → HA dashboard ✓

KROK 5: Provoz
  → Chromium kiosk mód, watchdog hlídá a restartuje při pádu
  → VNC / SSH pro vzdálenou správu (bez fyzického přístupu)
  → HA Addon zobrazuje stav a IP všech kiosků
  → Claude Code dostupný přes SSH pro AI-asistované úpravy
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
