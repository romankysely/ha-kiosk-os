# Modul: 03-claude-code

Viz dokumentaci: [docs/modules/claude-code.md](../../docs/modules/claude-code.md)

## Soubory modulu

- `start_chroot_script` — bash skript spuštěný v chroot při buildu
- `files/` — soubory kopírované do image (struktura odpovídá /)

## Co se instaluje

- Node.js 20 LTS (přes NodeSource)
- `@anthropic-ai/claude-code` (npm global, prefix `~/.npm-global`)
- PATH patch v `/home/pi/.bashrc`

## Autentizace (nutno udělat ručně po prvním bootu)

Claude Code vyžaduje OAuth přihlášení — nedá se automatizovat na headless systému.
Přihlásit se přes SSH s port forwardingem nebo zkopírovat credentials:

```bash
# Ze stroje kde je Claude přihlášen:
scp ~/.claude/credentials.json pi@192.168.1.101:~/.claude/
```

## Stav

Implementováno v1.0.0
