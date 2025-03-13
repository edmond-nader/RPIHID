#!/usr/bin/env bash
# deploy.sh
#
# This script deploys the RPIHID project by:
# 1. Installing missing dependencies.
# 2. Cloning the repository if essential files are not found.
# 3. Verifying that required core files are present (including the /wifi_config endpoint).
# 4. Copying files to their proper system locations.
# 5. Setting permissions.
# 6. Updating /etc/dhcpcd.conf for the virtual AP interface (uap0).
# 7. Ensuring the USB HID gadget is set up.
# 8. Reloading systemd and enabling required services.
#
# The system is configured to operate concurrently as a Wi-Fi client on wlan0
# and as an Access Point on virtual interface uap0 with a static IP of 192.168.4.1.
# The AP (SSID "MyRPZ") is always enabled on boot, and the web interface includes
# buttons for Wi-Fi configuration and hotspot control.
#
# Run with:
#   curl https://raw.githubusercontent.com/edmond-nader/RPIHID/refs/heads/testing/deploy.sh | sudo bash

set -euo pipefail

###############################
# 1. Ensure Running as Root and apt-get Availability
###############################
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not found. This script is for Debian-based systems."
    exit 1
fi

###############################
# 2. Install Missing Dependencies
###############################
deps=(hostapd dnsmasq iw python3 curl git dos2unix)
missing=()
for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing+=("$dep")
    fi
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Installing missing dependencies: ${missing[*]}"
    apt-get update
    apt-get install -y "${missing[@]}"
else
    echo "All dependencies are installed."
fi

###############################
# 3. Define Repository Directory
###############################
if [ -n "${BASH_SOURCE:-}" ]; then
    REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
else
    REPO_DIR="$(pwd)"
fi
echo "Initial repository directory: ${REPO_DIR}"

if [ ! -f "${REPO_DIR}/app.py" ]; then
    echo "Essential files not found in ${REPO_DIR}."
    echo "Cloning repository from GitHub..."
    REPO_URL="https://github.com/edmond-nader/RPIHID.git"
    TEMP_DIR=$(mktemp -d)
    git clone "${REPO_URL}" "${TEMP_DIR}" -b testing
    REPO_DIR="${TEMP_DIR}"
    echo "Repository cloned to ${REPO_DIR}."
fi

###############################
# 4. Verify Required Core Files
###############################
required_files=(
    "app.py"
    "setup-usb-hid.sh"
    "templates/keyboard.html"
    "templates/wifi_config.html"
    "scripts/flask-hid@.service"
    "scripts/update_wifi.sh"
    "configs/hostapd.conf"
    "configs/hostapd"
    "configs/ap-dnsmasq.conf"
)
for file in "${required_files[@]}"; do
    if [ ! -f "${REPO_DIR}/$file" ]; then
        echo "Error: ${REPO_DIR}/$file not found."
        exit 1
    fi
done
echo "All required core files are present."

if ! grep -q "def wifi_config(" "${REPO_DIR}/app.py"; then
    echo "Warning: app.py does not appear to contain a 'wifi_config' endpoint."
    echo "Please ensure your app.py defines a route for /wifi_config."
fi

# Warn for optional virtual interface creation files.
if [ ! -f "${REPO_DIR}/scripts/create_uap0.sh" ]; then
    echo "Warning: ${REPO_DIR}/scripts/create_uap0.sh not found."
    echo "For concurrent AP/client mode, please add this file to your repository."
fi
if [ ! -f "${REPO_DIR}/scripts/create-uap0.service" ]; then
    echo "Warning: ${REPO_DIR}/scripts/create-uap0.service not found."
    echo "For concurrent AP/client mode, please add this file to your repository."
fi

###############################
# 5. Deploy Files
###############################
INSTALL_PREFIX="/usr/local/bin"
TEMPLATES_DIR="${INSTALL_PREFIX}/templates"
SYSTEMD_DIR="/etc/systemd/system"
HOSTAPD_CONF_DIR="/etc/hostapd"
DEFAULT_HOSTAPD_DIR="/etc/default"
DNSMASQ_CONF_DIR="/etc/dnsmasq.d"

echo "Deploying app.py..."
cp "${REPO_DIR}/app.py" "${INSTALL_PREFIX}/app.py"
chmod +x "${INSTALL_PREFIX}/app.py"

echo "Deploying setup-usb-hid.sh..."
cp "${REPO_DIR}/setup-usb-hid.sh" "${INSTALL_PREFIX}/setup-usb-hid.sh"
chmod +x "${INSTALL_PREFIX}/setup-usb-hid.sh"

echo "Deploying templates..."
mkdir -p "${TEMPLATES_DIR}"
cp -r "${REPO_DIR}/templates/." "${TEMPLATES_DIR}/"

echo "Deploying flask-hid@.service..."
cp "${REPO_DIR}/scripts/flask-hid@.service" "${SYSTEMD_DIR}/flask-hid@.service"

echo "Deploying update_wifi.sh..."
cp "${REPO_DIR}/scripts/update_wifi.sh" "${INSTALL_PREFIX}/update_wifi.sh"
chmod 700 "${INSTALL_PREFIX}/update_wifi.sh"
chown root:root "${INSTALL_PREFIX}/update_wifi.sh"

if [ -f "${REPO_DIR}/scripts/create_uap0.sh" ]; then
    echo "Deploying create_uap0.sh..."
    cp "${REPO_DIR}/scripts/create_uap0.sh" "${INSTALL_PREFIX}/create_uap0.sh"
    chmod +x "${INSTALL_PREFIX}/create_uap0.sh"
else
    echo "Skipping create_uap0.sh (not found)."
fi

if [ -f "${REPO_DIR}/scripts/create-uap0.service" ]; then
    echo "Deploying create-uap0.service..."
    cp "${REPO_DIR}/scripts/create-uap0.service" "${SYSTEMD_DIR}/create-uap0.service"
else
    echo "Skipping create-uap0.service (not found)."
fi

echo "Deploying hostapd.conf..."
mkdir -p "${HOSTAPD_CONF_DIR}"
dos2unix "${REPO_DIR}/configs/hostapd.conf"
cp "${REPO_DIR}/configs/hostapd.conf" "${HOSTAPD_CONF_DIR}/hostapd.conf"

echo "Deploying default hostapd file..."
cp "${REPO_DIR}/configs/hostapd" "${DEFAULT_HOSTAPD_DIR}/hostapd"

echo "Deploying ap-dnsmasq.conf..."
mkdir -p "${DNSMASQ_CONF_DIR}"
cp "${REPO_DIR}/configs/ap-dnsmasq.conf" "${DNSMASQ_CONF_DIR}/ap-dnsmasq.conf"

if [ -f "${REPO_DIR}/configs/dnsmasq.service" ]; then
    echo "Deploying dnsmasq.service..."
    cp "${REPO_DIR}/configs/dnsmasq.service" "${SYSTEMD_DIR}/dnsmasq.service"
else
    echo "Skipping dnsmasq.service (not found); system unit will be used."
fi

###############################
# 6. Update /etc/dhcpcd.conf for uap0
###############################
if ! grep -q "interface uap0" /etc/dhcpcd.conf; then
    echo "Appending static IP configuration for uap0 to /etc/dhcpcd.conf..."
    cat <<EOF >> /etc/dhcpcd.conf

interface uap0
    static ip_address=192.168.4.1/24
EOF
fi
echo "/etc/dhcpcd.conf updated."

###############################
# 7. Ensure USB HID Gadget is Set Up
###############################
if [ ! -e /dev/hidg0 ]; then
    echo "/dev/hidg0 not found. Running setup-usb-hid.sh to initialize USB HID gadget..."
    /usr/local/bin/setup-usb-hid.sh
else
    echo "/dev/hidg0 found."
fi

###############################
# 8. Reload systemd and Enable Services
###############################
echo "Reloading systemd daemon..."
systemctl daemon-reload

if [ -f "/etc/systemd/system/create-uap0.service" ]; then
    echo "Enabling create-uap0.service..."
    systemctl enable create-uap0.service
    systemctl start create-uap0.service
elif [ -f "${INSTALL_PREFIX}/create_uap0.sh" ]; then
    echo "create-uap0.service not found, but create_uap0.sh exists. Running it directly..."
    /usr/local/bin/create_uap0.sh
else
    echo "Virtual interface creation file not found. Skipping."
fi

echo "Enabling hostapd..."
systemctl unmask hostapd
systemctl enable hostapd
systemctl restart hostapd

echo "Enabling dnsmasq..."
if systemctl list-unit-files --type=service | grep -E -q '^dnsmasq\.service'; then
    systemctl enable dnsmasq
    systemctl restart dnsmasq
else
    echo "dnsmasq.service not found. Enabling deployed dnsmasq.service if available..."
    if [ -f "/etc/systemd/system/dnsmasq.service" ]; then
        systemctl enable dnsmasq.service
        systemctl restart dnsmasq.service
    else
        echo "Warning: dnsmasq could not be restarted."
    fi
fi

CURRENT_USER="$(logname)"
echo "Enabling flask-hid@${CURRENT_USER}.service..."
systemctl enable flask-hid@${CURRENT_USER}.service
systemctl restart flask-hid@${CURRENT_USER}.service

echo "Deployment complete. Please reboot your system for all changes to take effect."
