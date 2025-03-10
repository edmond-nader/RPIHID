#!/bin/bash
# deploy.sh - Auto deploy script for Raspberry Pi HID keyboard with Wi-Fi configuration and fallback.
# This script installs required packages, deploys all files (app.py, setup-usb-hid.sh,
# update_wifi.sh, wifi_fallback.sh, and HTML templates), and creates systemd services.

set -euo pipefail

# Make sure the script is run as root.
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Try running with sudo."
  exit 1
fi

echo "Starting deployment..."

###############################
# 1. Install required packages
###############################
echo "Installing required packages..."
apt-get update
apt-get install -y hostapd dnsmasq iw python3 python3-pip

##################################################
# 2. Deploy setup-usb-hid.sh (enables HID keyboard mode)
##################################################
echo "Deploying setup-usb-hid.sh to /usr/local/bin..."
cat << 'EOF' > /usr/local/bin/setup-usb-hid.sh
#!/usr/bin/env bash
# Echo commands to stdout.
set -x
# Exit on first error and treat unset variables as errors.
set -e
set -u

# 1. Enable dwc2 overlay and module.
if ! grep -q 'dtoverlay=dwc2' /boot/config.txt; then
  echo "dtoverlay=dwc2" >> /boot/config.txt
fi

if ! grep -q '^dwc2' /etc/modules; then
  echo "dwc2" >> /etc/modules
fi

# 2. Create the HID initialization script at /opt/enable-rpi-hid.
HID_SCRIPT_PATH="/opt/enable-rpi-hid"
cat << 'EOS' > ${HID_SCRIPT_PATH}
#!/usr/bin/env bash
set -e
set -u

modprobe libcomposite

cd /sys/kernel/config/usb_gadget/
mkdir -p g1
cd g1

echo 0x1d6b > idVendor  # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0100 > bcdDevice # v1.0.0
echo 0x0200 > bcdUSB    # USB2

STRINGS_DIR="strings/0x409"
mkdir -p "$STRINGS_DIR"
echo "6b65796d696d6570690" > "${STRINGS_DIR}/serialnumber"
echo "keymimepi" > "${STRINGS_DIR}/manufacturer"
echo "Generic USB Keyboard" > "${STRINGS_DIR}/product"

FUNCTIONS_DIR="functions/hid.usb0"
mkdir -p "$FUNCTIONS_DIR"
echo 1 > "${FUNCTIONS_DIR}/protocol" # Keyboard
echo 0 > "${FUNCTIONS_DIR}/subclass"   # No subclass
echo 8 > "${FUNCTIONS_DIR}/report_length"
# Write the report descriptor.
echo -ne \\x05\\x01\\x09\\x06\\xa1\\x01\\x05\\x07\\x19\\xe0\\x29\\xe7\\x15\\x00\\x25\\x01\\x75\\x01\\x95\\x08\\x81\\x02\\x95\\x01\\x75\\x08\\x81\\x03\\x95\\x05\\x75\\x01\\x05\\x08\\x19\\x01\\x29\\x05\\x91\\x02\\x95\\x01\\x75\\x03\\x91\\x03\\x95\\x06\\x75\\x08\\x15\\x00\\x25\\x65\\x05\\x07\\x19\\x00\\x29\\x65\\x81\\x00\\xc0 > "${FUNCTIONS_DIR}/report_desc"

CONFIG_INDEX=1
CONFIGS_DIR="configs/c.${CONFIG_INDEX}"
mkdir -p "$CONFIGS_DIR"
echo 250 > "${CONFIGS_DIR}/MaxPower"

CONFIGS_STRINGS_DIR="${CONFIGS_DIR}/strings/0x409"
mkdir -p "$CONFIGS_STRINGS_DIR"
echo "Config ${CONFIG_INDEX}: ECM network" > "${CONFIGS_STRINGS_DIR}/configuration"

ln -s "$FUNCTIONS_DIR" "${CONFIGS_DIR}/"
ls /sys/class/udc > UDC

chmod 777 /dev/hidg0
EOS

chmod +x ${HID_SCRIPT_PATH}

# 3. Create the systemd service unit file for USB gadget.
SERVICE_PATH="/lib/systemd/system/usb-gadget.service"
cat << 'EOF' > ${SERVICE_PATH}
[Unit]
Description=Create virtual keyboard USB gadget
After=syslog.target

[Service]
Type=oneshot
User=root
ExecStart=/opt/enable-rpi-hid

[Install]
WantedBy=local-fs.target
EOF

# 4. Reload systemd daemon and enable the usb-gadget service.
systemctl daemon-reload
systemctl enable usb-gadget.service

echo "setup-usb-hid.sh deployed. (Reboot required for HID changes to take effect.)"

##################################################
# 3. Deploy update_wifi.sh helper script (secured update)
##################################################
echo "Deploying update_wifi.sh helper script to /usr/local/bin..."
cat << 'EOF' > /usr/local/bin/update_wifi.sh
#!/usr/bin/env bash
# update_wifi.sh
# This script updates the wpa_supplicant configuration with a new network block.
# It expects two parameters: SSID and password.
# The output of wpa_passphrase is filtered to remove the commented plain text password.

set -e
set -u

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <SSID> <PASSWORD>"
  exit 1
fi

SSID="$1"
PASSWORD="$2"

# Generate the network block and remove the commented plain text password.
NETWORK_CONFIG=$(wpa_passphrase "$SSID" "$PASSWORD" | sed '/^#psk=/d')

# Append the network block to /etc/wpa_supplicant/wpa_supplicant.conf.
echo "$NETWORK_CONFIG" >> /etc/wpa_supplicant/wpa_supplicant.conf
EOF

chown root:root /usr/local/bin/update_wifi.sh
chmod 700 /usr/local/bin/update_wifi.sh

# Configure sudoers to allow user "pi" to run update_wifi.sh without a password.
echo "Configuring sudoers for update_wifi.sh..."
echo "pi ALL=(root) NOPASSWD: /usr/local/bin/update_wifi.sh" > /etc/sudoers.d/update_wifi
chmod 440 /etc/sudoers.d/update_wifi

##################################################
# 4. Deploy wifi_fallback.sh (to start AP mode if no Wi-Fi)
##################################################
echo "Deploying wifi_fallback.sh to /usr/local/bin..."
cat << 'EOF' > /usr/local/bin/wifi_fallback.sh
#!/usr/bin/env bash
# wifi_fallback.sh
# Wait 30 seconds after boot and start hotspot mode if no Wi-Fi connection is present.

sleep 30

# Check if wlan0 has an IP address (i.e., if Wi-Fi is connected)
if ! /sbin/ip addr show wlan0 | grep -q "inet "; then
    echo "Wi-Fi not connected – starting hotspot mode..."
    sudo systemctl stop wpa_supplicant
    sudo ifconfig wlan0 down
    sudo ifconfig wlan0 up
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
else
    echo "Wi-Fi connected – hotspot not required."
    sudo systemctl stop hostapd || true
    sudo systemctl stop dnsmasq || true
fi
EOF

chmod +x /usr/local/bin/wifi_fallback.sh

# Create systemd service for wifi-fallback.
echo "Creating wifi-fallback systemd service..."
cat << 'EOF' > /etc/systemd/system/wifi-fallback.service
[Unit]
Description=WiFi Fallback Hotspot Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi_fallback.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wifi-fallback.service

##################################################
# 5. Deploy Flask HID Keyboard App (app.py)
##################################################
echo "Deploying app.py to /usr/local/bin..."
cat << 'EOF' > /usr/local/bin/app.py
#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify
import time
import subprocess
import re

app = Flask(__name__)

# --------------------
# HID Keyboard Part
# --------------------
KEY_MAP = {
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
    "enter": (0x00, 0x28),
    "esc": (0x00, 0x29),
    "backspace": (0x00, 0x2A),
    "tab": (0x00, 0x2B),
    "space": (0x00, 0x2C),
    "up": (0x00, 0x52),
    "down": (0x00, 0x51),
    "left": (0x00, 0x50),
    "right": (0x00, 0x4F)
}

HID_DEVICE = "/dev/hidg0"

def send_hid_report(modifier, key_code):
    press_report = bytes([modifier, 0x00, key_code, 0x00, 0x00, 0x00, 0x00, 0x00])
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

@app.route("/scan_wifi")
def scan_wifi():
    try:
        output = subprocess.check_output(["sudo", "iwlist", "wlan0", "scan"], universal_newlines=True)
        import re
        ssids = re.findall(r'ESSID:"([^"]+)"', output)
        ssids = list(set(ssids))
        return jsonify({"networks": ssids})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

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
            subprocess.call(["sudo", "systemctl", "stop", "hostapd"])
            subprocess.call(["sudo", "systemctl", "stop", "dnsmasq"])
            return jsonify({"success": True, "message": "Connected to Wi-Fi network."})
        else:
            return jsonify({"success": False, "error": "Connection failed, hotspot mode remains active."}), 500
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

# --------------------
# Shutdown Endpoint
# --------------------
shutdown_attempts = {}
COOLDOWN_PERIOD = 60  # seconds
MAX_ATTEMPTS = 3

@app.route("/shutdown", methods=["POST"])
def shutdown():
    ip = request.remote_addr
    now = time.time()
    attempts = shutdown_attempts.get(ip, {"count": 0, "lock_until": 0})
    if now < attempts.get("lock_until", 0):
        wait_time = int(attempts["lock_until"] - now)
        return jsonify({"success": False, "error": f"Too many attempts. Please wait {wait_time} seconds."}), 429
    token = request.form.get("token")
    if token != "MY_SHUTDOWN_TOKEN":
        attempts["count"] = attempts.get("count", 0) + 1
        if attempts["count"] >= MAX_ATTEMPTS:
            attempts["lock_until"] = now + COOLDOWN_PERIOD
            attempts["count"] = 0
        shutdown_attempts[ip] = attempts
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    shutdown_attempts[ip] = {"count": 0, "lock_until": 0}
    try:
        subprocess.call(["sudo", "shutdown", "-h", "now"])
        return jsonify({"success": True, "message": "System shutting down..."}), 200
    except Exception as e:
        return jsonify({"success": False, "error": f"Shutdown failed: {e}"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
EOF

chmod +x /usr/local/bin/app.py

##################################################
# 6. Deploy HTML templates
##################################################
echo "Deploying HTML templates..."
mkdir -p /usr/local/bin/templates

# keyboard.html
cat << 'EOF' > /usr/local/bin/templates/keyboard.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>RPi HID Keyboard</title>
  <style>
    /* Basic page styling */
    body {
      background-color: #222;
      color: #fff;
      margin: 0;
      padding: 20px;
      font-family: Arial, sans-serif;
      text-align: center;
    }
    h1 { margin-bottom: 10px; }
    /* Connection Indicator */
    #connectionIndicator {
      position: fixed;
      top: 10px;
      right: 10px;
      width: 15px;
      height: 15px;
      border-radius: 50%;
      background-color: red;
      border: 1px solid #fff;
      z-index: 1000;
    }
    /* Key press log */
    .key-log {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 8px;
      margin-bottom: 20px;
      width: 100%;
      box-sizing: border-box;
    }
    .key-press {
      background: #444;
      border-radius: 4px;
      padding: 5px 10px;
      opacity: 0;
      transition: opacity 0.5s;
      white-space: nowrap;
    }
    .key-press.visible { opacity: 1; }
    .key-press.fade-out { opacity: 0; }
    /* Container */
    .container { width: 100%; margin: 0 auto; }
    /* Arrow Keys */
    .arrow-keys { margin-bottom: 30px; }
    .arrow-row {
      display: flex;
      justify-content: center;
      flex-wrap: wrap;
      margin: 5px 0;
    }
    .arrow {
      background: #333;
      border: 1px solid #444;
      border-radius: 5px;
      margin: 5px;
      padding: 20px 30px;
      text-align: center;
      cursor: pointer;
      user-select: none;
      transition: background 0.2s;
      font-size: 1.5rem;
      min-width: 80px;
      min-height: 60px;
      white-space: nowrap;
    }
    .arrow:hover { background: #444; }
    .arrow:active { background: #555; }
    /* Main keyboard layout */
    .keyboard {
      display: flex;
      flex-direction: column;
      gap: 10px;
      align-items: center;
    }
    .row {
      display: flex;
      justify-content: center;
      flex-wrap: wrap;
      margin: 5px 0;
    }
    .key {
      background: #333;
      border: 1px solid #444;
      border-radius: 5px;
      margin: 5px;
      padding: 10px 15px;
      text-align: center;
      cursor: pointer;
      user-select: none;
      transition: background 0.2s;
      font-size: 1rem;
      min-width: 50px;
      white-space: nowrap;
    }
    .key:hover { background: #444; }
    .key:active { background: #555; }
    .wide { min-width: 80px; }
    /* Toggleable Text Input Section */
    .text-input-section { margin-top: 20px; }
    .text-input-section textarea {
      width: 80%;
      max-width: 500px;
      height: 100px;
      padding: 10px;
      font-size: 1rem;
      border-radius: 5px;
      border: 1px solid #444;
      background: #333;
      color: #fff;
      resize: vertical;
    }
    .text-input-section button {
      margin-top: 10px;
      padding: 10px 20px;
      font-size: 1rem;
      background: #555;
      border: 1px solid #444;
      border-radius: 5px;
      cursor: pointer;
      transition: background 0.2s;
    }
    .text-input-section button:hover { background: #666; }
    /* Buttons below the keyboard */
    #toggleTextInputButton, #showTouchpadButton, #shutdownButton, #wifiConfigButton {
      margin-top: 20px;
      padding: 10px 20px;
      font-size: 1rem;
      border: 1px solid #444;
      border-radius: 5px;
      cursor: pointer;
      transition: background 0.2s;
    }
    #toggleTextInputButton, #showTouchpadButton, #wifiConfigButton {
      background: #555;
      color: #fff;
    }
    #toggleTextInputButton:hover, #showTouchpadButton:hover, #wifiConfigButton:hover { background: #666; }
    #shutdownButton {
      background: #a00;
      color: #fff;
    }
    #shutdownButton:hover { background: #c00; }
    /* Responsive */
    @media (max-width: 600px) {
      .arrow { font-size: 1.3rem; padding: 15px 25px; min-width: 60px; min-height: 50px; }
      .key { font-size: 0.9rem; min-width: 40px; }
      .wide { min-width: 60px; }
      .text-input-section textarea { width: 90%; }
    }
  </style>
</head>
<body>
  <!-- Connection Status Indicator -->
  <div id="connectionIndicator"></div>
  
  <h1>Raspberry Pi HID Keyboard</h1>
  
  <!-- Key Press Log -->
  <div class="key-log" id="keyLog"></div>
  
  <div class="container">
    <!-- Arrow Keys -->
    <div class="arrow-keys">
      <div class="arrow-row">
        <div class="arrow" data-key="up">↑</div>
      </div>
      <div class="arrow-row">
        <div class="arrow" data-key="left">←</div>
        <div class="arrow" data-key="down">↓</div>
        <div class="arrow" data-key="right">→</div>
      </div>
      <div class="arrow-row">
        <div class="arrow" data-key="esc">ESC</div>
        <div class="arrow" data-key="b">B</div>
        <div class="arrow" data-key="f5">F5</div>
      </div>
    </div>

    <!-- Main Keyboard -->
    <div class="keyboard">
      <!-- Row 1: Function Keys -->
      <div class="row">
        <div class="key" data-key="f1">F1</div>
        <div class="key" data-key="f2">F2</div>
        <div class="key" data-key="f3">F3</div>
        <div class="key" data-key="f4">F4</div>
        <div class="key" data-key="f5">F5</div>
        <div class="key" data-key="f6">F6</div>
        <div class="key" data-key="f7">F7</div>
        <div class="key" data-key="f8">F8</div>
        <div class="key" data-key="f9">F9</div>
        <div class="key" data-key="f10">F10</div>
        <div class="key" data-key="f11">F11</div>
        <div class="key" data-key="f12">F12</div>
      </div>
      <!-- Row 2: Esc, Numbers, Backspace -->
      <div class="row">
        <div class="key" data-key="esc">Esc</div>
        <div class="key" data-key="1">1</div>
        <div class="key" data-key="2">2</div>
        <div class="key" data-key="3">3</div>
        <div class="key" data-key="4">4</div>
        <div class="key" data-key="5">5</div>
        <div class="key" data-key="6">6</div>
        <div class="key" data-key="7">7</div>
        <div class="key" data-key="8">8</div>
        <div class="key" data-key="9">9</div>
        <div class="key" data-key="0">0</div>
        <div class="key wide" data-key="backspace">Bksp</div>
      </div>
      <!-- Row 3: Q - P -->
      <div class="row">
        <div class="key" data-key="q">Q</div>
        <div class="key" data-key="w">W</div>
        <div class="key" data-key="e">E</div>
        <div class="key" data-key="r">R</div>
        <div class="key" data-key="t">T</div>
        <div class="key" data-key="y">Y</div>
        <div class="key" data-key="u">U</div>
        <div class="key" data-key="i">I</div>
        <div class="key" data-key="o">O</div>
        <div class="key" data-key="p">P</div>
      </div>
      <!-- Row 4: A - L, Enter -->
      <div class="row">
        <div class="key" data-key="a">A</div>
        <div class="key" data-key="s">S</div>
        <div class="key" data-key="d">D</div>
        <div class="key" data-key="f">F</div>
        <div class="key" data-key="g">G</div>
        <div class="key" data-key="h">H</div>
        <div class="key" data-key="j">J</div>
        <div class="key" data-key="k">K</div>
        <div class="key" data-key="l">L</div>
        <div class="key wide" data-key="enter">Enter</div>
      </div>
      <!-- Row 5: Z - M, Space -->
      <div class="row">
        <div class="key" data-key="z">Z</div>
        <div class="key" data-key="x">X</div>
        <div class="key" data-key="c">C</div>
        <div class="key" data-key="v">V</div>
        <div class="key" data-key="b">B</div>
        <div class="key" data-key="n">N</div>
        <div class="key" data-key="m">M</div>
        <div class="key wide" data-key="space">Space</div>
      </div>
    </div>

    <!-- Buttons Below the Keyboard -->
    <button id="toggleTextInputButton" onclick="toggleTextInput()">Show Text Input</button>
    <button id="shutdownButton" onclick="shutdownRPi()">Shutdown RPi</button>
    <button id="wifiConfigButton" onclick="location.href='/wifi_config'">Wi‑Fi Config</button>
    
    <!-- Text Input Section (hidden by default) -->
    <div id="textInputSection" class="text-input-section" style="display: none;">
      <textarea id="textInput" placeholder="Type or paste text here..."></textarea><br>
      <button onclick="sendText()">Send Text as Keystrokes</button>
    </div>
  </div>

  <script>
    // Attach click handlers to key and arrow elements.
    document.querySelectorAll('.key, .arrow').forEach(function(elem) {
      elem.addEventListener('click', function() {
        var key = this.getAttribute('data-key');
        sendKeyAjax(key);
        addKeyToLog(key);
      });
    });

    function sendKeyAjax(key) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/send_key", true);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
          if (xhr.status === 200) {
            document.getElementById("connectionIndicator").style.backgroundColor = "green";
          } else {
            document.getElementById("connectionIndicator").style.backgroundColor = "red";
          }
        }
      };
      xhr.send("key=" + encodeURIComponent(key));
    }

    function addKeyToLog(key) {
      const keyLog = document.getElementById('keyLog');
      const newItem = document.createElement('div');
      newItem.classList.add('key-press');
      newItem.textContent = key;
      keyLog.insertBefore(newItem, keyLog.firstChild);
      void newItem.offsetWidth;
      newItem.classList.add('visible');
      setTimeout(() => { removeKey(newItem); }, 30000);
      if (keyLog.children.length > 10) {
        removeKey(keyLog.lastChild);
      }
    }

    function removeKey(item) {
      if (!item) return;
      item.classList.remove('visible');
      item.classList.add('fade-out');
      setTimeout(() => {
        if (item.parentNode) { item.parentNode.removeChild(item); }
      }, 500);
    }

    function toggleTextInput() {
      const section = document.getElementById('textInputSection');
      const btn = document.getElementById('toggleTextInputButton');
      if (section.style.display === "none") {
        section.style.display = "block";
        btn.textContent = "Hide Text Input";
      } else {
        section.style.display = "none";
        btn.textContent = "Show Text Input";
      }
    }

    function sendText() {
      const rawText = document.getElementById('textInput').value.trim();
      if (!rawText) return;
      let i = 0;
      function sendNext() {
        if (i >= rawText.length) return;
        let key = null;
        if (rawText[i] === '{') {
          let end = rawText.indexOf('}', i);
          if (end !== -1) {
            key = rawText.substring(i + 1, end).toLowerCase();
            i = end + 1;
          } else {
            key = rawText[i];
            i++;
          }
        } else {
          key = rawText[i];
          i++;
          if (key === ' ') { key = 'space'; }
          else if (key.match(/[A-Z]/)) { key = key.toLowerCase(); }
        }
        sendKeyAjax(key);
        addKeyToLog(key);
        setTimeout(sendNext, 300);
      }
      sendNext();
    }

    function shutdownRPi() {
      var token = prompt("Enter shutdown token:");
      if (!token) return;
      if (confirm("Are you sure you want to shut down the Raspberry Pi?")) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "/shutdown", true);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function() {
          if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
              alert("Server is shutting down.");
            } else {
              alert("Shutdown failed: " + xhr.responseText);
            }
          }
        };
        xhr.send("token=" + encodeURIComponent(token));
      }
    }

    function checkConnection() {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", "/ping?ts=" + new Date().getTime(), true);
      xhr.timeout = 5000;
      xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
          if (xhr.status === 200) {
            document.getElementById("connectionIndicator").style.backgroundColor = "green";
          } else {
            document.getElementById("connectionIndicator").style.backgroundColor = "red";
          }
        }
      };
      xhr.ontimeout = function() { document.getElementById("connectionIndicator").style.backgroundColor = "red"; };
      xhr.onerror = function() { document.getElementById("connectionIndicator").style.backgroundColor = "red"; };
      xhr.send();
    }
    setInterval(checkConnection, 5000);
  </script>
</body>
</html>
EOF

# wifi_config.html
cat << 'EOF' > /usr/local/bin/templates/wifi_config.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Wi‑Fi Configuration</title>
    <style>
        body { font-family: Arial, sans-serif; background-color: #222; color: #fff; text-align: center; }
        .network { padding: 10px; border: 1px solid #444; margin: 5px; cursor: pointer; }
        input, button { padding: 10px; margin: 5px; }
    </style>
</head>
<body>
    <h1>Wi‑Fi Configuration</h1>
    <button onclick="scanWifi()">Scan for Networks</button>
    <div id="networks"></div>
    <hr>
    <h2>Connect to a Network</h2>
    <form id="wifiForm">
        <input type="text" id="ssid" placeholder="SSID" required><br>
        <input type="password" id="password" placeholder="Password" required><br>
        <button type="submit">Connect</button>
    </form>
    <div id="result"></div>
    <br>
    <button onclick="location.href='/'">Return to Keyboard</button>
    <script>
        function scanWifi() {
            fetch("/scan_wifi")
                .then(response => response.json())
                .then(data => {
                    const networksDiv = document.getElementById("networks");
                    networksDiv.innerHTML = "";
                    if (data.networks) {
                        data.networks.forEach(net => {
                            const div = document.createElement("div");
                            div.className = "network";
                            div.textContent = net;
                            div.onclick = () => { document.getElementById("ssid").value = net; };
                            networksDiv.appendChild(div);
                        });
                    } else {
                        networksDiv.textContent = "No networks found.";
                    }
                })
                .catch(err => console.error(err));
        }
        document.getElementById("wifiForm").addEventListener("submit", function(e) {
            e.preventDefault();
            const ssid = document.getElementById("ssid").value;
            const password = document.getElementById("password").value;
            const formData = new URLSearchParams();
            formData.append("ssid", ssid);
            formData.append("password", password);
            fetch("/connect_wifi", { method: "POST", body: formData })
                .then(response => response.json())
                .then(data => {
                    document.getElementById("result").textContent = data.message || data.error;
                })
                .catch(err => console.error(err));
        });
    </script>
</body>
</html>
EOF

##################################################
# 7. Create systemd service for Flask app.
##################################################
echo "Creating systemd service for Flask HID app..."
cat << 'EOF' > /etc/systemd/system/flask-hid.service
[Unit]
Description=Flask HID Keyboard Service
After=network.target

[Service]
User=pi
Group=pi
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/python3 /usr/local/bin/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flask-hid.service
systemctl start flask-hid.service

echo "Deployment complete. Please reboot the system if necessary."
