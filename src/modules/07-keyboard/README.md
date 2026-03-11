# Modul 07-keyboard — virtuální klávesnice

Volitelný modul pro dotykové kiosky. Instaluje **onboard** — virtuální klávesnici
která se automaticky zobrazí při kliknutí na textové pole v Chromiu.

## Kdy použít

Přidej tento modul do `MODULES` v `config/build.conf` pouze pokud má kiosk
**dotykový displej**. Na kiosky bez dotyku ho vynech.

```bash
# config/build.conf — dotykový kiosk
MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring 07-keyboard"

# config/build.conf — kiosk bez dotyku (výchozí)
MODULES="01-kiosk-base 02-vnc 03-claude-code 04-audio 05-ha-bootstrap 06-monitoring"
```

## Co se nainstaluje

- `onboard` — virtuální klávesnice pro X11
- `onboard-data` — rozložení klávesnic
- `at-spi2-core` — accessibility bus (nutný pro auto-show)

## Konfigurace

`files/home/pi/.config/onboard/onboard.conf`:
- `auto-show-enabled=true` — zobrazí se automaticky při focusu textového pole
- `layout=Phone` — kompaktní rozložení vhodné pro kiosk
- `always-on-top=true` — zobrazí se nad Chromiem
- `height=250` — přizpůsob podle velikosti displeje

## Přizpůsobení výšky klávesnice

Pokud je displej menší/větší, uprav `height` v `onboard.conf`:
- 7" displej → `height=180`
- 10" displej → `height=220`
- 15" displej → `height=280`
