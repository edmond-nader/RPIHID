#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify
import time, subprocess, re

app = Flask(__name__)

# --------------------
# HID Keyboard Endpoints
# --------------------
KEY_MAP = {
    "f1": (0x00, 0x3A), "f2": (0x00, 0x3B), "f3": (0x00, 0x3C),
    "f4": (0x00, 0x3D), "f5": (0x00, 0x3E), "f6": (0x00, 0x3F),
    "f7": (0x00, 0x40), "f8": (0x00, 0x41), "f9": (0x00, 0x42),
    "f10": (0x00, 0x43), "f11": (0x00, 0x44), "f12": (0x00, 0x45),
    "1": (0x00, 0x1E), "2": (0x00, 0x1F), "3": (0x00, 0x20),
    "4": (0x00, 0x21), "5": (0x00, 0x22), "6": (0x00, 0x23),
    "7": (0x00, 0x24), "8": (0x00, 0x25), "9": (0x00, 0x26),
    "0": (0x00, 0x27), "q": (0x00, 0x14), "w": (0x00, 0x1A),
    "e": (0x00, 0x08), "r": (0x00, 0x15), "t": (0x00, 0x17),
    "y": (0x00, 0x1C), "u": (0x00, 0x18), "i": (0x00, 0x0C),
    "o": (0x00, 0x12), "p": (0x00, 0x13), "a": (0x00, 0x04),
    "s": (0x00, 0x16), "d": (0x00, 0x07), "f": (0x00, 0x09),
    "g": (0x00, 0x0A), "h": (0x00, 0x0B), "j": (0x00, 0x0D),
    "k": (0x00, 0x0E), "l": (0x00, 0x0F), "z": (0x00, 0x1D),
    "x": (0x00, 0x1B), "c": (0x00, 0x06), "v": (0x00, 0x19),
    "b": (0x00, 0x05), "n": (0x00, 0x11), "m": (0x00, 0x10),
    "enter": (0x00, 0x28), "esc": (0x00, 0x29), "backspace": (0x00, 0x2A),
    "tab": (0x00, 0x2B), "space": (0x00, 0x2C), "up": (0x00, 0x52),
    "down": (0x00, 0x51), "left": (0x00, 0x50), "right": (0x00, 0x4F)
}

HID_DEVICE = "/dev/hidg0"

def send_hid_report(modifier, key_code):
    press_report = bytes([modifier, 0x00, key_code, 0, 0, 0, 0, 0])
    release_report = bytes(8)
    try:
        with open(HID_DEVICE, "wb") as fd:
            fd.write(press_report)
        time.sleep(0.1)
        with open(HID_DEVICE, "wb") as fd:
            fd.write(release_report)
        return True
    except Exception as e:
        print(f"Error sending HID report: {e}")
        return False

@app.route("/")
def index():
    return render_template("keyboard.html")

@app.route("/send_key", methods=["POST"])
def send_key():
    key = request.form.get("key")
    if key not in KEY_MAP:
        return jsonify({"success": False, "error": "Unknown key"}), 400
    modifier, key_code = KEY_MAP[key]
    if send_hid_report(modifier, key_code):
        return jsonify({"success": True})
    else:
        return jsonify({"success": False, "error": "Failed to write to HID device"}), 500

@app.route("/ping")
def ping():
    return "pong", 200

# --------------------
# Wi-Fi Configuration Endpoints
# --------------------
@app.route("/wifi_config")
def wifi_config():
    return render_template("wifi_config.html")

@app.route("/connect_wifi", methods=["POST"])
def connect_wifi():
    ssid = request.form.get("ssid")
    password = request.form.get("password")
    if not ssid or not password:
        return jsonify({"success": False, "error": "SSID and password required"}), 400
    try:
        subprocess.check_call(["sudo", "/usr/local/bin/update_wifi.sh", ssid, password])
        subprocess.check_call(["sudo", "wpa_cli", "-i", "wlan0", "reconfigure"])
        time.sleep(10)
        output = subprocess.check_output(["/sbin/ip", "addr", "show", "wlan0"], universal_newlines=True)
        if "inet " in output:
            return jsonify({"success": True, "message": "Connected to Wi-Fi network."})
        else:
            return jsonify({"success": False, "error": "Connection failed."}), 500
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/scan_wifi")
def scan_wifi():
    try:
        # Run the scan command; may require sudo privileges.
        output = subprocess.check_output(["sudo", "iwlist", "wlan0", "scan"], universal_newlines=True)
        # Use regex to extract ESSIDs.
        ssids = re.findall(r'ESSID:"([^"]+)"', output)
        # Remove empty entries and duplicates.
        ssids = list(set([s for s in ssids if s]))
        return jsonify({"networks": ssids})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --------------------
# Hotspot Control Endpoints
# --------------------
@app.route("/disable_hotspot", methods=["POST"])
def disable_hotspot():
    try:
        subprocess.check_call(["sudo", "systemctl", "stop", "hostapd"])
        subprocess.check_call(["sudo", "systemctl", "stop", "dnsmasq"])
        return jsonify({"success": True, "message": "Hotspot disabled."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/enable_hotspot", methods=["POST"])
def enable_hotspot():
    try:
        subprocess.check_call(["sudo", "systemctl", "start", "hostapd"])
        subprocess.check_call(["sudo", "systemctl", "start", "dnsmasq"])
        return jsonify({"success": True, "message": "Hotspot enabled."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
