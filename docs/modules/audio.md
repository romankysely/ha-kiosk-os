# Modul 04-audio

## Co dělá

Instaluje audio stack pro kiosk:
- **PipeWire** — moderní audio server (výchozí v Bookworm)
- **Snapcast klient** — příjem multi-room audio streamů z HA/Music Assistant
- **TTS přehrávání** — kiosk přehrává TTS notifikace z HA

## Proč PipeWire (ne PulseAudio)

RPi OS Bookworm (2024+) používá PipeWire jako výchozí audio server.
PipeWire je zpětně kompatibilní s PulseAudio API — veškerý software
co fungoval s PulseAudio funguje i s PipeWire bez změn.

Výhody PipeWire:
- Nižší latence
- Lepší Bluetooth podpora
- Stabilnější při přepínání zdrojů

## Co se instaluje

```
pipewire
pipewire-pulse       # PulseAudio kompatibilita
wireplumber          # Session manager pro PipeWire
snapclient           # Snapcast klient
```

## Jak funguje audio v HA kiosk kontextu

```
HA / Music Assistant
    → Snapcast server (běží na HA)
    → LAN stream
    → Snapcast klient (na kiosku)
    → PipeWire → audio výstup kiosku

HA TTS notifikace
    → notify.mobile_app nebo media_player
    → Snapcast nebo přímý audio výstup
    → PipeWire → reproduktor
```

## Snapcast klient konfigurace

`/etc/default/snapclient`:
```
SNAPCLIENT_OPTS="-h HA_SNAPCAST_IP --player alsa"
```

Hodnota `HA_SNAPCAST_IP` se doplní z `kiosk.conf` při firstboot.

### Systemd service
```bash
sudo systemctl enable snapclient
sudo systemctl start snapclient
```

## Audio výstup

Pi5 má více audio výstupů:
- **HDMI 0** — zvuk přes HDMI kabel do monitoru
- **HDMI 1** — druhý HDMI port
- **USB audio** — externí USB DAC/reproduktor
- **Bluetooth** — BT reproduktor

Výchozí výstup se nastavuje v `kiosk.conf`:
```
KIOSK_AUDIO_OUTPUT=hdmi0   # hdmi0 | hdmi1 | usb | bluetooth
```

## TTS v HA

Kiosk jako target pro TTS notifikace z HA:
1. Snapcast klient → Music Assistant player
2. Přímý `media_player` entity v HA

Příklad HA automation:
```yaml
action: tts.speak
target:
  entity_id: tts.piper
data:
  media_player_entity_id: media_player.kiosk_obyvak
  message: "Pohyb detekován u vchodových dveří"
```

## Troubleshooting

### Žádný zvuk

```bash
# Status PipeWire
systemctl --user status pipewire
systemctl --user status wireplumber

# Seznam audio zařízení
pactl list sinks short
wpctl status

# Test zvuku
speaker-test -t wav -c 2
```

### Snapcast se nepřipojí k HA

```bash
# Status snapclient
sudo systemctl status snapclient
journalctl -u snapclient -n 50

# Ping HA Snapcast server
ping -c 3 192.168.1.100

# Snapcast port (výchozí 1704)
nc -zv 192.168.1.100 1704
```

### HDMI audio nefunguje

```bash
# Zobraz výstup
pactl list sinks | grep -A5 "HDMI"

# Nastav jako výchozí
pactl set-default-sink alsa_output.platform-fef00700.hdmi.hdmi-stereo

# Trvalé nastavení
echo "set-default-sink alsa_output.platform-fef00700.hdmi.hdmi-stereo" \
  >> /etc/pipewire/pipewire.conf.d/default-sink.conf
```

## Changelog

| Verze | Změna |
|-------|-------|
| 1.0.0 | PipeWire + Snapcast klient |
