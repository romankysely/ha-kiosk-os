#!/usr/bin/env python3
"""
HA KioskOS — Kiosk Builder Addon
Flask web server + REST API pro správu kiosků
"""

import json
import os
import subprocess
import datetime
from pathlib import Path
from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, flash

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "ha-kiosk-os-secret-change-me")

# ---------------------------------------------------------------------------
# Cesty k datovým souborům
# ---------------------------------------------------------------------------
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
KIOSKS_FILE = DATA_DIR / "kiosks.json"
SSH_PRIVATE_KEY = DATA_DIR / "kiosk_builder_rsa"
SSH_PUBLIC_KEY = DATA_DIR / "kiosk_builder_rsa.pub"
KIOSKS_DIR = DATA_DIR / "kiosks"

# Kiosk download URL (přepíše konfiguraci z HA)
DOWNLOAD_URL = os.environ.get(
    "KIOSK_DOWNLOAD_URL",
    "https://github.com/romankysely/ha-kiosk-os/releases/latest/download/ha-kiosk-os.img.xz"
)


# ---------------------------------------------------------------------------
# Pomocné funkce pro persistenci
# ---------------------------------------------------------------------------

def load_kiosks() -> dict:
    """Načte databázi kiosků z JSON souboru."""
    if KIOSKS_FILE.exists():
        try:
            return json.loads(KIOSKS_FILE.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, IOError):
            return {}
    return {}


def save_kiosks(kiosks: dict) -> None:
    """Uloží databázi kiosků do JSON souboru."""
    KIOSKS_DIR.mkdir(parents=True, exist_ok=True)
    KIOSKS_FILE.write_text(
        json.dumps(kiosks, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )


def get_ssh_public_key() -> str:
    """Vrátí obsah SSH public key nebo prázdný string."""
    if SSH_PUBLIC_KEY.exists():
        return SSH_PUBLIC_KEY.read_text(encoding="utf-8").strip()
    return ""


def kiosk_is_online(kiosk: dict, timeout_minutes: int = 5) -> bool:
    """Vrátí True pokud kiosk kontaktoval addon v posledních N minutách."""
    last_seen = kiosk.get("last_seen")
    if not last_seen:
        return False
    try:
        last_dt = datetime.datetime.fromisoformat(last_seen)
        delta = datetime.datetime.now() - last_dt
        return delta.total_seconds() < timeout_minutes * 60
    except (ValueError, TypeError):
        return False


def generate_kiosk_conf(data: dict) -> str:
    """Vygeneruje obsah kiosk.conf ze slovníku dat."""
    ssh_pub = get_ssh_public_key()
    lines = [
        "################################################################################",
        f"# kiosk.conf — vygenerováno HA KioskOS Kiosk Builderem",
        f"# Datum: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "# NIKDY necommituj tento soubor do gitu!",
        "################################################################################",
        "",
        f'KIOSK_HOSTNAME="{data.get("hostname", "kiosk")}"',
        "",
        f'KIOSK_HA_URL="{data.get("ha_url", "")}"',
        f'KIOSK_HA_TOKEN="{data.get("ha_token", "")}"',
        f'KIOSK_ADDON_URL="{data.get("addon_url", "")}"',
        "",
        f'KIOSK_DASHBOARD_URL="{data.get("dashboard_url", "")}"',
        "",
        f'KIOSK_NETWORK="{data.get("network", "dhcp")}"',
        f'KIOSK_WIFI_SSID="{data.get("wifi_ssid", "")}"',
        f'KIOSK_WIFI_PASSWORD="{data.get("wifi_password", "")}"',
        f'KIOSK_STATIC_IP="{data.get("static_ip", "")}"',
        f'KIOSK_STATIC_GATEWAY="{data.get("static_gateway", "")}"',
        f'KIOSK_STATIC_DNS="{data.get("static_dns", "8.8.8.8")}"',
        "",
        f'KIOSK_RESOLUTION="{data.get("resolution", "1920x1080")}"',
        f'KIOSK_ROTATION="{data.get("rotation", "0")}"',
        "",
        f'KIOSK_AUDIO_OUTPUT="{data.get("audio_output", "hdmi0")}"',
        f'KIOSK_SNAPCAST_HOST="{data.get("snapcast_host", "")}"',
    ]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Web UI routes
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    """Dashboard — seznam všech kiosků."""
    kiosks = load_kiosks()
    # Přidat online status
    for hostname, kiosk in kiosks.items():
        kiosk["online"] = kiosk_is_online(kiosk)
        kiosk["hostname"] = hostname
    return render_template("index.html",
                           kiosks=list(kiosks.values()),
                           download_url=DOWNLOAD_URL)


@app.route("/add", methods=["GET", "POST"])
def add_kiosk():
    """Formulář pro přidání nového kiosku a generování kiosk.conf."""
    if request.method == "POST":
        data = {
            "hostname": request.form.get("hostname", "").strip().lower(),
            "ha_url": request.form.get("ha_url", "").strip().rstrip("/"),
            "ha_token": request.form.get("ha_token", "").strip(),
            "addon_url": request.form.get("addon_url", "").strip().rstrip("/"),
            "dashboard_url": request.form.get("dashboard_url", "").strip(),
            "network": request.form.get("network", "dhcp"),
            "wifi_ssid": request.form.get("wifi_ssid", "").strip(),
            "wifi_password": request.form.get("wifi_password", "").strip(),
            "static_ip": request.form.get("static_ip", "").strip(),
            "static_gateway": request.form.get("static_gateway", "").strip(),
            "static_dns": request.form.get("static_dns", "8.8.8.8").strip(),
            "resolution": request.form.get("resolution", "1920x1080"),
            "rotation": request.form.get("rotation", "0"),
            "audio_output": request.form.get("audio_output", "hdmi0"),
            "snapcast_host": request.form.get("snapcast_host", "").strip(),
        }

        if not data["hostname"]:
            flash("Hostname je povinný.", "error")
            return render_template("add.html", data=data)

        # Uložit kiosk do databáze
        kiosks = load_kiosks()
        kiosks[data["hostname"]] = {
            **data,
            "created": datetime.datetime.now().isoformat(),
            "last_seen": None,
            "last_ip": None,
            "registered": False,
        }
        save_kiosks(kiosks)

        # Vygenerovat kiosk.conf
        conf_content = generate_kiosk_conf(data)
        conf_path = KIOSKS_DIR / f"{data['hostname']}.conf"
        conf_path.write_text(conf_content, encoding="utf-8")

        flash(f"Kiosk '{data['hostname']}' přidán. Stáhni kiosk.conf.", "success")
        return redirect(url_for("download_conf", hostname=data["hostname"]))

    # GET — prázdný formulář s výchozími hodnotami
    default_data = {
        "hostname": "",
        "ha_url": "http://192.168.1.100:8123",
        "ha_token": "",
        "addon_url": "http://192.168.1.100:8099",
        "dashboard_url": "http://192.168.1.100:8123/lovelace/0",
        "network": "dhcp",
        "wifi_ssid": "",
        "wifi_password": "",
        "static_ip": "",
        "static_gateway": "",
        "static_dns": "8.8.8.8",
        "resolution": "1920x1080",
        "rotation": "0",
        "audio_output": "hdmi0",
        "snapcast_host": "",
    }
    return render_template("add.html", data=default_data)


@app.route("/kiosk/<hostname>")
def kiosk_detail(hostname: str):
    """Detail kiosku — log, nastavení, akce."""
    kiosks = load_kiosks()
    kiosk = kiosks.get(hostname)
    if not kiosk:
        flash(f"Kiosk '{hostname}' nenalezen.", "error")
        return redirect(url_for("index"))
    kiosk["online"] = kiosk_is_online(kiosk)
    kiosk["hostname"] = hostname
    return render_template("detail.html", kiosk=kiosk)


@app.route("/kiosk/<hostname>/delete", methods=["POST"])
def delete_kiosk(hostname: str):
    """Smaže kiosk z databáze."""
    kiosks = load_kiosks()
    if hostname in kiosks:
        del kiosks[hostname]
        save_kiosks(kiosks)
        # Smaž conf soubor
        conf_path = KIOSKS_DIR / f"{hostname}.conf"
        conf_path.unlink(missing_ok=True)
        flash(f"Kiosk '{hostname}' smazán.", "success")
    return redirect(url_for("index"))


@app.route("/download/<hostname>/kiosk.conf")
def download_conf(hostname: str):
    """Stažení vygenerovaného kiosk.conf pro daný kiosk."""
    conf_path = KIOSKS_DIR / f"{hostname}.conf"
    if not conf_path.exists():
        kiosks = load_kiosks()
        kiosk = kiosks.get(hostname)
        if not kiosk:
            return "Kiosk nenalezen", 404
        conf_content = generate_kiosk_conf(kiosk)
        conf_path.write_text(conf_content, encoding="utf-8")

    return send_file(
        conf_path,
        as_attachment=True,
        download_name="kiosk.conf",
        mimetype="text/plain"
    )


@app.route("/wizard")
def wizard():
    """Průvodce instalací krok za krokem."""
    return render_template("wizard.html", download_url=DOWNLOAD_URL)


# ---------------------------------------------------------------------------
# REST API — phone-home endpoint (volá firstboot.sh na RPi)
# ---------------------------------------------------------------------------

@app.route("/api/register", methods=["POST"])
def api_register():
    """
    Phone-home endpoint — RPi se zaregistruje při firstboot.
    Vrátí SSH public key addonu pro authorized_keys na RPi.

    Request body (JSON):
      { "hostname": "kiosk1", "mac": "aa:bb:cc:dd:ee:ff", "ip": "192.168.1.101" }

    Response (JSON):
      { "status": "ok", "ssh_public_key": "ssh-rsa AAAA..." }
    """
    try:
        payload = request.get_json(silent=True) or {}
    except Exception:
        payload = {}

    hostname = payload.get("hostname", "unknown")
    mac = payload.get("mac", "")
    client_ip = payload.get("ip") or request.remote_addr

    # Aktualizovat status kiosku v databázi
    kiosks = load_kiosks()
    now = datetime.datetime.now().isoformat()

    if hostname not in kiosks:
        # Auto-přidat neznámý kiosk (bez kiosk.conf dat)
        kiosks[hostname] = {
            "hostname": hostname,
            "created": now,
            "auto_registered": True,
        }

    kiosks[hostname].update({
        "last_seen": now,
        "last_ip": client_ip,
        "mac": mac,
        "registered": True,
    })
    save_kiosks(kiosks)

    # Vrátit SSH public key
    ssh_pub = get_ssh_public_key()

    response = {
        "status": "ok",
        "hostname": hostname,
        "registered_at": now,
        "ssh_public_key": ssh_pub,
    }

    app.logger.info(f"Phone-home: {hostname} ({client_ip}, MAC: {mac})")
    return jsonify(response), 200


@app.route("/api/kiosks", methods=["GET"])
def api_kiosks():
    """Vrátí seznam kiosků jako JSON (pro případnou integraci)."""
    kiosks = load_kiosks()
    result = []
    for hostname, kiosk in kiosks.items():
        result.append({
            "hostname": hostname,
            "online": kiosk_is_online(kiosk),
            "last_seen": kiosk.get("last_seen"),
            "last_ip": kiosk.get("last_ip"),
            "registered": kiosk.get("registered", False),
        })
    return jsonify(result)


@app.route("/api/ssh-key", methods=["GET"])
def api_ssh_key():
    """Vrátí SSH public key addonu."""
    return jsonify({"ssh_public_key": get_ssh_public_key()})


# ---------------------------------------------------------------------------
# Spuštění serveru
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Zajistit existenci datových adresářů
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    KIOSKS_DIR.mkdir(parents=True, exist_ok=True)

    port = int(os.environ.get("PORT", 8099))
    debug = os.environ.get("FLASK_DEBUG", "false").lower() == "true"

    app.logger.info(f"HA KioskOS Kiosk Builder spuštěn na portu {port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
