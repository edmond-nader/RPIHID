#!/usr/bin/env bash
# deploy.sh
# This script deploys the RPIHID project by:
#  1. Installing any missing dependencies.
#  2. Checking for repository files; if missing, cloning the full repository.
#  3. Copying files to their proper system locations.
#  4. Setting up permissions.
#  5. Running the USB HID setup script if needed.
#  6. Reloading systemd and enabling/restarting necessary services.
#
# Run with:
#   curl https://raw.githubusercontent.com/edmond-nader/RPIHID/refs/heads/main/deploy.sh | sudo bash

set -euo pipefail

###############################
# 1. Ensure Running as Root and apt-get Availability
###############################
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please run with sudo."
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: apt-get is not available. This script is intended for Debian-based systems."
    exit 1
fi

###############################
# 2. Install Missing Dependencies
###############################
# Added git to dependency list.
dependencies=(hostapd dnsmasq iw python3 curl git)
missing=()
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing+=("$dep")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "Installing missing dependencies: ${missing[*]}"
    apt-get update
    apt-get install -y "${missing[@]}"
else
    echo "All dependencies are already installed."
fi

###############################
# 3. Define Repository and Target Directories
###############################
# Determine REPO_DIR from the location of this script.
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "Initial repository directory: ${REPO_DIR}"

# If required file(s) are not present, assume the repository wasn't fully downloaded.
if [ ! -f "${REPO_DIR}/app.py" ]; then
    echo "Repository files not found in ${REPO_DIR}."
    echo "Cloning repository from GitHub..."
    REPO_URL="https://github.com/edmond-nader/RPIHID.git"
    TEMP_REPO=$(mktemp -d)
    git clone "${REPO_URL}" "${TEMP_REPO}" -b testing
    REPO_DIR="${TEMP_REPO}"
    echo "Repository cloned to ${REPO_DIR}."
fi

# Define target directories.
INSTALL_PREFIX="/usr/local/bin"
TEMPLATES_DIR="${INSTALL_PREFIX}/templates"
SYSTEMD_DIR="/etc/systemd/system"
HOSTAPD_CONF_DIR="/etc/hostapd"
DEFAULT_HOSTAPD_DIR="/etc/default"

###############################
# 4. Verify Required Files Exist
###############################
check_file() {
    if [ ! -f "$1" ]; then
        echo "Error: Required file '$1' not found. Please ensure your repository is complete."
        exit 1
    fi
}

check_file "${REPO_DIR}/app.py"
check_file "${REPO_DIR}/setup-usb-hid.sh"
check_file "${REPO_DIR}/templates/keyboard.html"
check_file "${REPO_DIR}/templates/wifi_config.html"
check_file "${REPO_DIR}/scripts/flask-hid@.service"
check_file "${REPO_DIR}/scripts/update_wifi.sh"
check_file "${REPO_DIR}/scripts/wifi-fallback.service"
check_file "${REPO_DIR}/scripts/wifi_fallback.sh"
check_file "${REPO_DIR}/configs/hostapd.conf"
check_file "${REPO_DIR}/configs/hostapd"

echo "All required files are present."

###############################
# 5. Deploy Files
###############################
echo "Deploying files..."

# 5.1 Deploy app.py to /usr/local/bin/app.py
echo "Deploying app.py to ${INSTALL_PREFIX}/app.py..."
cp "${REPO_DIR}/app.py" "${INSTALL_PREFIX}/app.py"
chmod +x "${INSTALL_PREFIX}/app.py"

# 5.2 Deploy setup-usb-hid.sh to /usr/local/bin/setup-usb-hid.sh
echo "Deploying setup-usb-hid.sh to ${INSTALL_PREFIX}/setup-usb-hid.sh..."
cp "${REPO_DIR}/setup-usb-hid.sh" "${INSTALL_PREFIX}/setup-usb-hid.sh"
chmod +x "${INSTALL_PREFIX}/setup-usb-hid.sh"

# 5.3 Deploy templates to /usr/local/bin/templates
echo "Deploying templates to ${TEMPLATES_DIR}..."
mkdir -p "${TEMPLATES_DIR}"
cp -r "${REPO_DIR}/templates/." "${TEMPLATES_DIR}/"

# 5.4 Deploy flask-hid@.service to systemd
echo "Deploying flask-hid@.service to ${SYSTEMD_DIR}/..."
cp "${REPO_DIR}/scripts/flask-hid@.service" "${SYSTEMD_DIR}/flask-hid@.service"

# 5.5 Deploy update_wifi.sh to /usr/local/bin/update_wifi.sh
echo "Deploying update_wifi.sh to ${INSTALL_PREFIX}/update_wifi.sh..."
cp "${REPO_DIR}/scripts/update_wifi.sh" "${INSTALL_PREFIX}/update_wifi.sh"
chmod 700 "${INSTALL_PREFIX}/update_wifi.sh"
chown root:root "${INSTALL_PREFIX}/update_wifi.sh"

# 5.6 Deploy wifi-fallback.service to systemd
echo "Deploying wifi-fallback.service to ${SYSTEMD_DIR}/..."
cp "${REPO_DIR}/scripts/wifi-fallback.service" "${SYSTEMD_DIR}/wifi-fallback.service"

# 5.7 Deploy wifi_fallback.sh to /usr/local/bin/wifi_fallback.sh
echo "Deploying wifi_fallback.sh to ${INSTALL_PREFIX}/wifi_fallback.sh..."
cp "${REPO_DIR}/scripts/wifi_fallback.sh" "${INSTALL_PREFIX}/wifi_fallback.sh"
chmod +x "${INSTALL_PREFIX}/wifi_fallback.sh"

# 5.8 Deploy hostapd.conf to /etc/hostapd/hostapd.conf
echo "Deploying hostapd.conf to ${HOSTAPD_CONF_DIR}/hostapd.conf..."
mkdir -p "${HOSTAPD_CONF_DIR}"
cp "${REPO_DIR}/configs/hostapd.conf" "${HOSTAPD_CONF_DIR}/hostapd.conf"

# 5.9 Deploy default hostapd file to /etc/default/hostapd
echo "Deploying hostapd (default file) to ${DEFAULT_HOSTAPD_DIR}/hostapd..."
cp "${REPO_DIR}/configs/hostapd" "${DEFAULT_HOSTAPD_DIR}/hostapd"

###############################
# 6. Generate usb-gadget.service if Not Present
###############################
if [ ! -f /lib/systemd/system/usb-gadget.service ]; then
    echo "usb-gadget.service not found. Running setup-usb-hid.sh to generate it..."
    /usr/local/bin/setup-usb-hid.sh
fi

###############################
# 7. Systemd Reload and Service Enablement
###############################
echo "Reloading systemd daemon..."
systemctl daemon-reload

# 7.1 Enable usb-gadget.service
echo "Enabling usb-gadget.service..."
systemctl enable usb-gadget.service || echo "usb-gadget.service may already be enabled."

# 7.2 Enable flask-hid@.service instance for the current login user.
CURRENT_USER="$(logname)"
echo "Enabling flask-hid@${CURRENT_USER}.service..."
systemctl enable flask-hid@${CURRENT_USER}.service
systemctl restart flask-hid@${CURRENT_USER}.service

# 7.3 Enable wifi-fallback.service
echo "Enabling wifi-fallback.service..."
systemctl enable wifi-fallback.service
systemctl restart wifi-fallback.service

echo "Deployment complete. Please reboot your system for all changes to take effect."
