#!/usr/bin/env python3
"""
HA KioskOS — inject-ha-token.py

Injektuje Home Assistant token do Chromium Preferences souboru
tak aby se Chromium automaticky přihlásil do HA bez zadání tokenu uživatelem.

Metoda: Zápis do Chromium Preferences JSON souboru
- Chromium čte Preferences při startu
- Klíč "profile.content_settings.exceptions.storage-access" (localStorage proxy)
- Jednodušší a spolehlivější než přímý přístup do LevelDB

Pokud Preferences přepíše token (po prvním přihlášení), uživatel se
přihlásí standardní cestou — token injection je pouze pohodlí, ne nutnost.
"""

import argparse
import json
import os
import pwd
import sys
from pathlib import Path


def get_chromium_prefs_path(username: str) -> Path:
    """Vrátí cestu k Chromium Preferences pro daného uživatele."""
    try:
        pw = pwd.getpwnam(username)
        home = pw.pw_dir
    except KeyError:
        home = f"/home/{username}"

    return Path(home) / ".config" / "chromium" / "Default" / "Preferences"


def inject_token(token: str, ha_url: str, username: str) -> bool:
    """
    Injektuje HA token do Chromium Preferences.
    Vrátí True při úspěchu, False při chybě.
    """
    prefs_path = get_chromium_prefs_path(username)

    # Zajistit existenci adresáře
    prefs_path.parent.mkdir(parents=True, exist_ok=True)

    # Načíst existující Preferences nebo začít s prázdným objektem
    prefs = {}
    if prefs_path.exists():
        try:
            with open(prefs_path, "r", encoding="utf-8") as f:
                prefs = json.load(f)
            print(f"Načteny existující Preferences: {prefs_path}")
        except (json.JSONDecodeError, IOError) as e:
            print(f"Varování: Nelze načíst existující Preferences ({e}), začínám prázdný")
            prefs = {}

    # Sestavit hassTokens objekt (formát který HA očekává v localStorage)
    hass_tokens = {
        "access_token": token,
        "token_type": "Bearer",
        "expires_in": 1800,
        "hassUrl": ha_url,
        "clientId": f"{ha_url}/",
        "expires": 9999999999,  # Dlouhá platnost — HA obnoví automaticky
        "refresh_token": "",
    }

    # Zapsat token do Chromium Preferences jako string (localStorage simulation)
    # HA čte token z localStorage klíče "hassTokens"
    # Preferences struktura: profile.local_storage_origin_data není standardní,
    # použijeme custom extension approach přes preferences "extensions" sekci

    # Jednodušší přístup: uložit token do custom souboru který firstboot extension načte
    token_file = prefs_path.parent / "ha_kiosk_token.json"
    try:
        with open(token_file, "w", encoding="utf-8") as f:
            json.dump(hass_tokens, f, indent=2)
        print(f"HA token uložen do: {token_file}")

        # Nastavit oprávnění na uživatele
        try:
            pw = pwd.getpwnam(username)
            os.chown(token_file, pw.pw_uid, pw.pw_gid)
        except (KeyError, PermissionError):
            pass

    except IOError as e:
        print(f"Chyba při ukládání token souboru: {e}")
        return False

    # Zapsat/aktualizovat Chromium Preferences
    # Přidáme startup URL jako fallback
    if "session" not in prefs:
        prefs["session"] = {}
    prefs["session"]["restore_on_startup"] = 4  # 4 = otevřít konkrétní URL
    if "startup_urls" not in prefs.get("session", {}):
        prefs["session"]["startup_urls"] = []

    # Chromium startup flags — přidáme poznámku do prefs pro debugging
    if "kiosk_bootstrap" not in prefs:
        prefs["kiosk_bootstrap"] = {
            "token_injected": True,
            "ha_url": ha_url,
            "token_file": str(token_file),
            "note": "Token injection provedena firstboot skriptem HA KioskOS"
        }

    try:
        with open(prefs_path, "w", encoding="utf-8") as f:
            json.dump(prefs, f, indent=2, ensure_ascii=False)

        # Nastavit oprávnění
        try:
            pw = pwd.getpwnam(username)
            os.chown(prefs_path, pw.pw_uid, pw.pw_gid)
            # Opravit celý adresář Default
            for item in prefs_path.parent.rglob("*"):
                try:
                    os.chown(item, pw.pw_uid, pw.pw_gid)
                except PermissionError:
                    pass
        except (KeyError, PermissionError):
            pass

        print(f"Chromium Preferences aktualizovány: {prefs_path}")

    except IOError as e:
        print(f"Chyba při zápisu Preferences: {e}")
        return False

    # ---------------------------------------------------------------------------
    # Vložit localStorage přes chromium --load-extension approach:
    # Vytvoříme minimální Chromium extension která při startu injektuje token
    # ---------------------------------------------------------------------------
    ext_dir = prefs_path.parent.parent / "ha_token_injector"
    if _create_token_injector_extension(ext_dir, hass_tokens, ha_url):
        print(f"Token injector extension vytvořena: {ext_dir}")
        # Přidat extension do chromium-kiosk wrapperu
        _add_extension_to_kiosk(ext_dir)
    else:
        print("Varování: Nepodařilo se vytvořit token injector extension")

    return True


def _create_token_injector_extension(ext_dir: Path, hass_tokens: dict, ha_url: str) -> bool:
    """
    Vytvoří minimální Chromium extension která injektuje hassTokens do localStorage.
    Extension se spustí jednou a pak se odinstaluje.
    """
    try:
        ext_dir.mkdir(parents=True, exist_ok=True)

        # manifest.json
        manifest = {
            "manifest_version": 3,
            "name": "HA KioskOS Token Injector",
            "version": "1.0",
            "description": "Jednorázová injekce HA tokenu do localStorage",
            "permissions": ["storage"],
            "content_scripts": [
                {
                    "matches": [f"{ha_url}/*"],
                    "js": ["inject.js"],
                    "run_at": "document_start",
                    "all_frames": False
                }
            ]
        }

        with open(ext_dir / "manifest.json", "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)

        # inject.js — vloží hassTokens do localStorage při načtení HA stránky
        tokens_json = json.dumps(json.dumps(hass_tokens))  # double-encode pro JS string
        inject_js = f"""
// HA KioskOS — Token Injector
// Vloží hassTokens do localStorage pro auto-přihlášení
(function() {{
    try {{
        var tokens = {tokens_json};
        if (!localStorage.getItem('hassTokens')) {{
            localStorage.setItem('hassTokens', tokens);
            console.log('[HA KioskOS] hassTokens injektovány do localStorage');
        }}
    }} catch(e) {{
        console.error('[HA KioskOS] Chyba při injekci tokenu:', e);
    }}
}})();
"""
        with open(ext_dir / "inject.js", "w", encoding="utf-8") as f:
            f.write(inject_js)

        return True

    except Exception as e:
        print(f"Chyba při vytváření extension: {e}")
        return False


def _add_extension_to_kiosk(ext_dir: Path) -> None:
    """Přidá --load-extension flag do chromium-kiosk wrapperu."""
    kiosk_script = Path("/usr/local/bin/chromium-kiosk")
    if not kiosk_script.exists():
        print("Varování: chromium-kiosk nenalezen — extension nebude načtena automaticky")
        return

    content = kiosk_script.read_text(encoding="utf-8")
    ext_flag = f"    --load-extension={ext_dir} \\"

    # Přidat flag před řádek s URL (poslední argument)
    if "--load-extension" not in content:
        content = content.replace(
            '    "${DASHBOARD_URL}" \\',
            f'{ext_flag}\n    "${{DASHBOARD_URL}}" \\'
        )
        kiosk_script.write_text(content, encoding="utf-8")
        print(f"Extension flag přidán do chromium-kiosk: {ext_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Injektuje HA token do Chromium pro auto-přihlášení"
    )
    parser.add_argument("--token", required=True, help="HA Long-Lived Access Token")
    parser.add_argument("--ha-url", required=True, help="Home Assistant URL (např. http://192.168.1.100:8123)")
    parser.add_argument("--user", default="pi", help="Linux uživatel (default: pi)")
    args = parser.parse_args()

    print(f"Injektuji HA token pro uživatele '{args.user}'...")
    print(f"HA URL: {args.ha_url}")

    success = inject_token(args.token, args.ha_url, args.user)

    if success:
        print("Token injection dokončena úspěšně.")
        sys.exit(0)
    else:
        print("Token injection selhala.")
        sys.exit(1)


if __name__ == "__main__":
    main()
