# Bezpečnost a soukromí

## Pravidlo č. 1

**Žádné citlivé informace NIKDY nejdou do gitu.**

Tento repozitář je navržen tak, aby mohl být veřejný nebo sdílený
bez úniku jakýchkoliv soukromých dat.

---

## Co je citlivé (NIKDY do gitu)

| Typ dat | Příklad | Kde žije |
|---------|---------|----------|
| WiFi hesla | `password=MojeHeslo123` | kiosk.conf (lokálně) |
| HA URL | `http://192.168.1.100:8123` | kiosk.conf (lokálně) |
| HA tokeny | `eyJ0eXAi...` | kiosk.conf (lokálně) |
| SSH privátní klíče | `id_ed25519` | HA Addon data (lokálně) |
| IP adresy | `192.168.1.101` | kiosk.conf (lokálně) |
| Hesla uživatelů | `password: raspberry` | RPi Imager (lokálně) |
| Hostname konkrétního kiosku | `kiosk-01` | kiosk.conf (lokálně) |

---

## Kde citlivé informace žijí

```
HA Addon (v /data/ na HA serveru)
    → kiosks.json — seznam kiosků se všemi detaily
    → SSH klíče — generované pro každý kiosk
    → HA tokeny — generované pro každý kiosk
    → /data/ je mimo git, je součástí HA backupu

SD karta → boot oddíl
    → kiosk.conf — generovaný z HA Addonu
    → obsahuje: HA URL, token, WiFi, hostname
    → smaže se automaticky po firstboot!

RPi Imager (pouze v paměti / lokálně)
    → heslo uživatele pi
    → nikam se neukládá mimo SD kartu
```

---

## kiosk.conf — životní cyklus

```
1. Uživatel klikne "Generovat kiosk.conf" v HA Addonu
2. Addon vygeneruje soubor s citlivými daty
3. Uživatel stáhne soubor (přes HTTPS)
4. Uživatel zkopíruje na SD kartu (boot oddíl)
5. RPi přečte kiosk.conf při firstboot
6. firstboot.sh SMAŽE kiosk.conf z boot oddílu
7. Citlivá data jsou uložena pouze v zašifrované části OS
```

---

## SSH přístup

Každý kiosk má **unikátní SSH keypair** generovaný v HA Addonu:
- Privátní klíč: uložen v HA Addon `/data/` (součást HA backupu)
- Veřejný klíč: zapsán do kiosku při firstboot

```bash
# Přístup na kiosk
ssh -i ~/.ssh/kiosk-01 pi@192.168.1.101

# Nebo přes HA Addon UI → SSH Console (plánovaná funkce)
```

**Heslo SSH přihlášení je zakázáno** — pouze klíče.

---

## HA token pro kiosk

Každý kiosk dostane **long-lived access token** s omezenými právy:
- Jen čtení dashboardů
- Přístup k WebRTC/kamera streamům
- Žádná práva ke správě HA

Token se injektuje do Chromium localStorage při firstboot.
Chromium se otevře automaticky přihlášený — uživatel nezadává heslo.

---

## .gitignore — co je chráněno

```gitignore
# Lokální konfigurace s citlivými daty
config/kiosk.conf
config/kiosk-*.conf
*.conf.local
.env
.env.local

# SSH klíče
*.pem
id_rsa
id_rsa.pub
id_ed25519
id_ed25519.pub
*.key

# HA Addon runtime data
ha-addon/app/data/
ha-addon/data/
data/

# Build artefakty (velké soubory)
*.img
*.img.xz
*.zip
src/image/
workspace/
```

---

## Sdílení repozitáře

Repozitář je bezpečné:
- ✅ Udělat veřejným na GitHubu
- ✅ Sdílet s komunitou
- ✅ Použít jako základ pro ostatní

Před sdílením ověř:
```bash
git log --all --full-history -- "*.conf"
git log --all --full-history -- "*password*"
git log --all --full-history -- "*token*"
```
Žádný z těchto souborů by neměl být v historii.
