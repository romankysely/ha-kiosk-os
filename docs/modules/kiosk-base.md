# Modul 01-kiosk-base

## Co dělá

Základ kiosk systému. Instaluje a konfiguruje:
- Autologin uživatele `pi` do konzole
- X server (Xorg)
- Openbox window manager (minimalistický, bez dekorací)
- Chromium v kiosk módu
- Hardware video dekódování (Pi5 — V4L2, H.264/HEVC)
- Skrytý kurzor
- Watchdog service pro restart Chromium

## Co se instaluje

```
xorg
openbox
chromium-browser
unclutter          # skrytí kurzoru
x11-xserver-utils  # xrandr, xset
libv4l-dev         # V4L2 pro HW video dekódování
```

## Konfigurace

### Autologin
`/etc/systemd/system/getty@tty1.service.d/autologin.conf`
- Automaticky přihlásí uživatele `pi` na TTY1 bez hesla

### X server start
`/home/pi/.bash_profile`
- Pokud jsme na TTY1 a DISPLAY není nastaven → spustí `startx`

### Openbox
`/home/pi/.config/openbox/autostart`
- xset: vypnutí screensaveru a DPMS
- unclutter: skryje kurzor po 1 vteřině nečinnosti
- Chromium kiosk wrapper

`/home/pi/.config/openbox/rc.xml`
- Žádné dekorace oken
- Maximalizace všech oken

### Chromium kiosk wrapper
`/usr/local/bin/chromium-kiosk`

Spouští Chromium s těmito flagy:
```
--kiosk                           # plná obrazovka, bez lišty
--no-first-run                    # přeskočit uvítací obrazovku
--disable-infobars                # žádné informační lišty
--disable-session-crashed-bubble  # žádné hlášení o pádu
--disable-restore-session-state   # neobnovovat starou session
--disable-translate               # žádný překladač
--disable-pinch                   # zakázat pinch zoom
--overscroll-history-navigation=0 # zakázat swipe navigaci
--autoplay-policy=no-user-gesture-required  # autoplay médií
--enable-features=VaapiVideoDecoder         # HW video dekódování
--enable-features=VaapiVideoEncoder         # HW video enkódování
--use-gl=egl                      # EGL pro GPU akceleraci
--ignore-gpu-blocklist            # použít GPU i když je na blocklist
```

### Pi5 specifické
`/boot/firmware/config.txt`:
```
usb_max_current_enable=1    # USB-A port: 600mA → 1600mA
                            # Nutné pro napájení monitoru přes USB
```

### Hardware video dekódování
Pi5 má dedikovaný video dekodér. Bez HW dekódování:
- CPU při WebRTC kameře: ~80-100%
- S HW dekódováním: ~10-15%

Konfigurace: `/etc/chromium-browser/customizations/01-hw-video`

## Watchdog

Service: `/etc/systemd/system/kiosk-watchdog.service`
Script: `/usr/local/bin/kiosk-watchdog.sh`

Každých 15 sekund zkontroluje zda běží Chromium.
Pokud ne → spustí znovu.

Log: `/var/log/kiosk-watchdog.log`

## Rozlišení a rotace

Nastavuje se přes `kiosk.conf` při firstboot:
- `KIOSK_RESOLUTION=1920x1080`
- `KIOSK_ROTATION=0` (0/1/2/3 = 0°/90°/180°/270°)

## Splash screen

Vlastní splash PNG: `/boot/firmware/splash.png`
Rozměr: 1920×1080 (nebo rozlišení displeje)

## Troubleshooting

### Chromium se nespustí
```bash
# Zkontroluj log watchdogu
cat /var/log/kiosk-watchdog.log

# Spusť ručně pro debug
DISPLAY=:0 chromium-kiosk 2>&1 | head -50
```

### Černá obrazovka po bootu
```bash
# Zkontroluj zda běží X server
pgrep Xorg

# Zkontroluj Openbox
pgrep openbox

# Ruční start
sudo -u pi startx 2>&1 | head -20
```

### HW video dekódování nefunguje
```bash
# Ověř V4L2
ls /dev/video*
v4l2-ctl --list-devices

# Chromium log
DISPLAY=:0 chromium-browser --enable-logging --v=1 \
  2>&1 | grep -i "vaapi\|v4l2\|video"
```

## Changelog

| Verze | Změna |
|-------|-------|
| 1.0.0 | Počáteční verze |
