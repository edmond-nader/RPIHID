#!/usr/bin/env bash
# deploy.sh
# This script deploys the RPIHID project by copying files to their target locations,
# setting up permissions, and enabling systemd services.
#
# It can be run via:
#   curl https://raw.githubusercontent.com/edmond-nader/RPIHID/refs/heads/main/deploy.sh | sudo bash

set -euo pipefail

# Check if running as root.
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please run with sudo."
    exit 1
fi

# Determine the repository root directory.
# Assume the script is located in the repository root.
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define target directories.
INSTALL_PREFIX="/usr/local/bin"
TEMPLATES_DIR="${INSTALL_PREFIX}/templates"
SYSTEMD_DIR="/etc/systemd/system"
HOSTAPD_CONF_DIR="/etc/hostapd"
DEFAULT_HOSTAPD_DIR="/etc/default"

echo "Starting deployment from repository: ${REPO_DIR}"

###############################
# 1. Check Dependencies
###############################
dependencies=(hostapd dnsmasq iw python3 curl)
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "Error: '$dep' is not installed. Please install it and rerun this script."
        exit 1
    fi
done
echo "All dependencies are installed."

###############################
# 2. Deploy Files
###############################

# 2.1 Deploy app.py to /usr/local/bin/app.py
echo "Deploying app.py to ${INSTALL_PREFIX}/app.py..."
cp "${REPO_DIR}/app.py" "${INSTALL_PREFIX}/app.py"
chmod +x "${INSTALL_PREFIX}/app.py"

# 2.2 Deploy setup-usb-hid.sh to /usr/local/bin/setup-usb-hid.sh
echo "Deploying setup-usb-hid.sh to ${INSTALL_PREFIX}/setup-usb-hid.sh..."
cp "${REPO_DIR}/setup-usb-hid.sh" "${INSTALL_PREFIX}/setup-usb-hid.sh"
chmod +x "${INSTALL_PREFIX}/setup-usb-hid.sh"

# 2.3 Deploy templates to /usr/local/bin/templates
echo "Deploying templates to ${TEMPLATES_DIR}..."
mkdir -p "${TEMPLATES_DIR}"
cp -r "${REPO_DIR}/templates/." "${TEMPLATES_DIR}/"

# 2.4 Deploy flask-hid@.service to systemd
echo "Deploying flask-hid@.service to ${SYSTEMD_DIR}/..."
cp "${REPO_DIR}/scripts/flask-hid@.service" "${SYSTEMD_DIR}/flask-hid@.service"

# 2.5 Deploy update_wifi.sh to /usr/local/bin/update_wifi.sh
echo "Deploying update_wifi.sh to ${INSTALL_PREFIX}/update_wifi.sh..."
cp "${REPO_DIR}/scripts/update_wifi.sh" "${INSTALL_PREFIX}/update_wifi.sh"
chmod 700 "${INSTALL_PREFIX}/update_wifi.sh"
chown root:root "${INSTALL_PREFIX}/update_wifi.sh"

# 2.6 Deploy wifi-fallback.service to systemd
echo "Deploying wifi-fallback.service to ${SYSTEMD_DIR}/..."
cp "${REPO_DIR}/scripts/wifi-fallback.service" "${SYSTEMD_DIR}/wifi-fallback.service"

# 2.7 Deploy wifi_fallback.sh to /usr/local/bin/wifi_fallback.sh
echo "Deploying wifi_fallback.sh to ${INSTALL_PREFIX}/wifi_fallback.sh..."
cp "${REPO_DIR}/scripts/wifi_fallback.sh" "${INSTALL_PREFIX}/wifi_fallback.sh"
chmod +x "${INSTALL_PREFIX}/wifi_fallback.sh"

# 2.8 Deploy hostapd.conf to /etc/hostapd/hostapd.conf
echo "Deploying hostapd.conf to ${HOSTAPD_CONF_DIR}/hostapd.conf..."
mkdir -p "${HOSTAPD_CONF_DIR}"
cp "${REPO_DIR}/configs/hostapd.conf" "${HOSTAPD_CONF_DIR}/hostapd.conf"

# 2.9 Deploy default hostapd file to /etc/default/hostapd
echo "Deploying hostapd (default file) to ${DEFAULT_HOSTAPD_DIR}/hostapd..."
cp "${REPO_DIR}/configs/hostapd" "${DEFAULT_HOSTAPD_DIR}/hostapd"

###############################
# 3. Systemd Reload and Service Enablement
###############################
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable usb-gadget.service (created by setup-usb-hid.sh)
echo "Enabling usb-gadget.service..."
systemctl enable usb-gadget.service || echo "usb-gadget.service may already be enabled."

# Determine the current user for the instance unit.
# Use logname so that if running under sudo, the original login user is used.
CURRENT_USER="$(logname)"
echo "Enabling flask-hid@${CURRENT_USER}.service..."
systemctl enable flask-hid@${CURRENT_USER}.service
systemctl restart flask-hid@${CURRENT_USER}.service

# Enable wifi-fallback.service
echo "Enabling wifi-fallback.service..."
systemctl enable wifi-fallback.service
systemctl restart wifi-fallback.service

echo "Deployment complete. Please reboot your system for all changes to take effect."
