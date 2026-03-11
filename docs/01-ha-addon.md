# HA Addon — Kiosk Builder

Webové rozhraní pro správu kiosků integrované přímo do Home Assistant.

## Co Addon dělá

| Funkce | Popis |
|--------|-------|
| Přidat kiosk | Formulář → generuje `kiosk.conf` ke stažení |
| Registrace RPi | Phone-home z `firstboot.sh` → RPi se automaticky přihlásí |
| Přehled kiosků | Seznam všech kiosků, online status, IP adresa, poslední aktivita |
| SSH klíč | Addon generuje SSH keypair → veřejný klíč se injektuje do kiosků |
| Detail kiosku | Hostname, HA user, dashboard URL, MAC, IP, SSH příkaz pro připojení |

---

## Instalace Addonu do Home Assistant

### Metoda A — Přes HA Addon Store (doporučeno)

1. HA → **Settings → Add-ons → Add-on Store** (pravý dolní roh)
2. Klikni na **⋮ → Repositories**
3. Přidej URL repozitáře:
   ```
   https://github.com/romankysely/ha-kiosk-os
   ```
4. Klikni **Add → Close**
5. Obnov stránku (F5) → v obchodě se zobrazí **HA KioskOS — Kiosk Builder**
6. Klikni na addon → **Install** (~2 min)
7. Záložka **Info** → **Start**
9. Přepni **Start on boot** a **Watchdog** na ON

### Metoda B — Lokální addon (pro vývoj a testování)

Pokud máš SSH přístup k HA hostu (HAOS nebo Supervised):

```bash
# SSH do HA hostu (port 22222 pro HAOS)
ssh root@homeassistant.local -p 22222

# Zkopíruj ha-addon/ do /addons/
mkdir -p /addons/ha_kiosk_os
# Pak z Windows/PC přes SCP:
scp -P 22222 -r ha-addon/* root@homeassistant.local:/addons/ha_kiosk_os/
```

V HA → Settings → Add-ons → **Local add-ons** (spodek stránky) → Kiosk Builder → Install.

---


## Jak přidat kiosk (krok za krokem)

### Předpoklady

Nejdříve v HA vytvoř uživatelský účet pro kiosk:
1. **Settings → People → Add Person**
2. Jméno: např. `Kiosk Obývák`, přihlašovací jméno: `kiosk-obyvak`
3. Přihlaš se do HA jako nový uživatel → vpravo nahoře profil →
   scroll dolů → **Long-Lived Access Tokens → Create Token**
4. Zkopíruj token (zobrazí se jen jednou!)

### Přidání kiosku v Addonu

1. Otevři **Kiosk Builder** v HA sidebaru
2. Klikni **Přidat kiosk**
3. Vyplň formulář:

| Pole | Příklad | Popis |
|------|---------|-------|
| Hostname | `kiosk-obyvak` | Síťové jméno RPi (bez .local) |
| HA URL | `http://192.168.1.50:8123` | Adresa tvého HA — bez lomítka na konci |
| HA Username | `kiosk-obyvak` | Přihlašovací jméno HA uživatele (ne zobrazené jméno) |
| HA Token (LLAT) | `eyJ0eXA...` | Long-Lived Access Token z HA profilu |
| Dashboard URL | `http://192.168.1.50:8123/lovelace/obyvak` | URL dashboardu — zkopíruj z prohlížeče |
| Moduly | `01-kiosk-base 02-vnc ...` | Mezery jako oddělovač |

4. Klikni **Uložit** → stáhni `kiosk.conf`

### kiosk.conf — co obsahuje

```bash
KIOSK_HOSTNAME="kiosk-obyvak"
KIOSK_HA_URL="http://192.168.1.50:8123"
KIOSK_HA_USERNAME="kiosk-obyvak"
KIOSK_HA_TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
KIOSK_DASHBOARD_URL="http://192.168.1.50:8123/lovelace/obyvak"
KIOSK_MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring"
KIOSK_NETWORK="dhcp"
KIOSK_SSH_KEY="ssh-rsa AAAA..."   # generuje addon automaticky
```

**Pozor:** Soubor obsahuje token — nechovej ho veřejně. Po firstbootu se automaticky smaže z SD karty.

---

## Phone-home registrace

Po firstbootu se RPi automaticky přihlásí do Addonu (pokud je kiosk.conf v pořádku):

```
RPi firstboot.sh → POST /api/register → Kiosk Builder
{
  "hostname": "kiosk-obyvak",
  "ha_username": "kiosk-obyvak",
  "dashboard_url": "http://...",
  "mac": "dc:a6:32:xx:xx:xx",
  "ip": "192.168.1.101"
}
```

Po registraci:
- Kiosk se zobrazí v seznamu Addonu
- Status: **Online** (zelená tečka)
- SSH klíč addonu je injektován do kiosku → přímý SSH přístup bez hesla

---

## Správa kiosků

### Přehledová stránka

Zobrazuje všechny registrované kiosky:
- **Zelená tečka** — kiosk kontaktoval addon v posledních 5 min
- **Šedá tečka** — kiosk offline nebo ještě neprovedl firstboot

### Detail kiosku

Kliknutím na kiosk zobrazíš:
- Hostname, IP, MAC, HA uživatel, dashboard URL
- Čas registrace a poslední aktivity
- SSH příkaz pro přímé připojení:
  ```bash
  ssh -i ~/.ssh/kiosk_builder_rsa pi@192.168.1.101
  ```

---

## Troubleshooting

### Addon nespustí — chyba v logu

```
Settings → Add-ons → Kiosk Builder → Log
```

Nejčastější příčiny:
- Chybný formát v Configuration → zkontroluj YAML
- Port 8099 je obsazený jiným addonem

### RPi se nezaregistroval (kiosk není v seznamu)

```bash
# Na RPi zkontroluj firstboot log
cat /var/log/kiosk-firstboot.log

# Hledej řádky s "Phone-home" a "register"
# Pokud chyba 404 → zkontroluj IP addonu v kiosk.conf (KIOSK_HA_URL)
# Pokud Connection refused → addon neběží nebo špatný port
```

### Addon není v sidebaru HA

Settings → Add-ons → Kiosk Builder → **Show in sidebar** → zapnout

