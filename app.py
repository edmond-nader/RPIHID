#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify
import time

app = Flask(__name__)

# Mapping of keys to HID key codes (scan codes)
# Each key is defined as a tuple: (modifier, key_code)
KEY_MAP = {
    # Function Keys
    "f1": (0x00, 0x3A),
    "f2": (0x00, 0x3B),
    "f3": (0x00, 0x3C),
    "f4": (0x00, 0x3D),
    "f5": (0x00, 0x3E),
    "f6": (0x00, 0x3F),
    "f7": (0x00, 0x40),
    "f8": (0x00, 0x41),
    "f9": (0x00, 0x42),
    "f10": (0x00, 0x43),
    "f11": (0x00, 0x44),
    "f12": (0x00, 0x45),
    # Numbers
    "1": (0x00, 0x1E),
    "2": (0x00, 0x1F),
    "3": (0x00, 0x20),
    "4": (0x00, 0x21),
    "5": (0x00, 0x22),
    "6": (0x00, 0x23),
    "7": (0x00, 0x24),
    "8": (0x00, 0x25),
    "9": (0x00, 0x26),
    "0": (0x00, 0x27),
    # Letters
    "q": (0x00, 0x14),
    "w": (0x00, 0x1A),
    "e": (0x00, 0x08),
    "r": (0x00, 0x15),
    "t": (0x00, 0x17),
    "y": (0x00, 0x1C),
    "u": (0x00, 0x18),
    "i": (0x00, 0x0C),
    "o": (0x00, 0x12),
    "p": (0x00, 0x13),
    "a": (0x00, 0x04),
    "s": (0x00, 0x16),
    "d": (0x00, 0x07),
    "f": (0x00, 0x09),
    "g": (0x00, 0x0A),
    "h": (0x00, 0x0B),
    "j": (0x00, 0x0D),
    "k": (0x00, 0x0E),
    "l": (0x00, 0x0F),
    "z": (0x00, 0x1D),
    "x": (0x00, 0x1B),
    "c": (0x00, 0x06),
    "v": (0x00, 0x19),
    "b": (0x00, 0x05),
    "n": (0x00, 0x11),
    "m": (0x00, 0x10),
    # Control Keys
    "enter": (0x00, 0x28),
    "esc": (0x00, 0x29),
    "backspace": (0x00, 0x2A),
    "tab": (0x00, 0x2B),
    "space": (0x00, 0x2C),
    # Arrow Keys
    "up": (0x00, 0x52),
    "down": (0x00, 0x51),
    "left": (0x00, 0x50),
    "right": (0x00, 0x4F)
}

HID_DEVICE = "/dev/hidg0"

def send_hid_report(modifier, key_code):
    """
    Send an 8-byte HID report.
    Report format: [modifier, reserved, key1, key2, key3, key4, key5, key6]
    This function sends a key press event followed by a release.
    """
    press_report = bytes([modifier, 0x00, key_code, 0x00, 0x00, 0x00, 0x00, 0x00])
    release_report = bytes(8)  # All zeros signify key release
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

# Add a ping endpoint to support connection monitoring.
@app.route("/ping")
def ping():
    return "pong", 200

if __name__ == "__main__":
    # Listen on all interfaces to allow access from other devices (e.g., your phone)
    app.run(host="0.0.0.0", port=5000, debug=True)
