# Modul 03-claude-code

## Co dělá

Instaluje **Node.js 20 LTS** a **Claude Code CLI** pro vzdálené AI-asistované
úpravy konfigurace kiosku přes SSH.

Toto je jeden z hlavních důvodů proč přecházíme z FullpageOS (32-bit armhf)
na RPi OS Lite 64-bit — Claude Code vyžaduje aarch64.

## Co se instaluje

```
nodejs 20.x LTS    # přes NodeSource repository
npm
@anthropic-ai/claude-code  # globálně přes npm
```

## Proč npm, ne native installer

Native installer Claude Code má bug na aarch64 (označuje architekturu jako "arm"
místo "arm64"). npm instalace funguje spolehlivě.

Viz: https://github.com/anthropics/claude-code/issues/3569

## npm global prefix

Claude Code se instaluje do uživatelského npm prefix (ne system):
```
~/.npm-global/bin/claude
```

Přidáno do PATH v `/home/pi/.bashrc`:
```bash
export PATH=~/.npm-global/bin:$PATH
```

## Autentizace Claude Code

**Důležité**: Claude Code vyžaduje autentizaci při prvním použití.
Na headless kiosku nelze otevřít prohlížeč pro OAuth.

### Řešení: zkopírovat credentials z jiného stroje

Na stroji kde máš Claude Code přihlášený (PC, Kali VM...):
```bash
scp ~/.claude/.credentials.json pi@kiosk-hostname:~/.claude/.credentials.json
```

Pak na kiosku:
```bash
# Nastav příznak dokončení onboardingu
nano ~/.claude.json
# Přidej nebo změň: "hasCompletedOnboarding": true
```

### Alternativa: přihlásit se přes SSH + port forward

```bash
# Na svém PC — SSH tunnel pro OAuth callback
ssh -L 8888:localhost:8888 pi@kiosk-hostname

# Na kiosku (přes SSH)
claude --port 8888
# Zkopíruj URL, otevři na svém PC
```

## Jak používat Claude Code na kiosku

```bash
# Přihlásit se na kiosk
ssh -i ~/.ssh/kiosk-01 pi@192.168.1.101

# Spustit Claude Code
claude

# Příklady použití
claude "Zkontroluj log watchdogu a řekni mi co je špatně"
claude "Uprav Chromium flagy v /usr/local/bin/chromium-kiosk"
claude "Zobraz posledních 50 řádků /var/log/kiosk-firstboot.log"
```

## Poznámky k výkonu

Claude Code na Pi5 je **plně použitelný**:
- Idle RAM: ~0 MB (žádný daemon)
- RAM při použití: ~150-300 MB
- CPU: minimální (čeká na Anthropic API)
- Vše je network-bound, ne CPU-bound

## Aktualizace Claude Code

```bash
# Na kiosku přes SSH
npm update -g @anthropic-ai/claude-code

# Nebo přes Claude Code samotný
claude update
```

## Troubleshooting

### "command not found: claude"
```bash
# Zkontroluj PATH
echo $PATH | grep npm-global
source ~/.bashrc

# Kde je claude?
find ~/.npm-global -name "claude" 2>/dev/null
```

### "Unsupported architecture"
```bash
# Ověř architekturu
uname -m
# Musí být: aarch64

dpkg --print-architecture
# Musí být: arm64 (NE armhf!)
```

### Autentizace selže
```bash
# Zkontroluj credentials
cat ~/.claude/.credentials.json
ls -la ~/.claude/

# Znovu přihlásit (viz sekce Autentizace výše)
```

## Changelog

| Verze | Změna |
|-------|-------|
| 1.0.0 | Node.js 20, Claude Code přes npm |
