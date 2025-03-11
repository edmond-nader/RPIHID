#!/usr/bin/env bash
# update_wifi.sh
# This script updates the wpa_supplicant configuration with a new network block.
# It expects two parameters: SSID and password.
# It filters out the plain-text password (commented out) so only the hashed PSK is appended.

set -e
set -u

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <SSID> <PASSWORD>"
  exit 1
fi

SSID="$1"
PASSWORD="$2"

# Generate the network block and remove the commented plain-text password.
NETWORK_CONFIG=$(wpa_passphrase "$SSID" "$PASSWORD" | sed '/^#psk=/d')

# Append the network block to /etc/wpa_supplicant/wpa_supplicant.conf.
echo "$NETWORK_CONFIG" >> /etc/wpa_supplicant/wpa_supplicant.conf
