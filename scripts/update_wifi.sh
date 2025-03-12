#!/usr/bin/env bash
# update_wifi.sh
# Updates /etc/wpa_supplicant/wpa_supplicant.conf with a new network block,
# filtering out the plain-text password.
set -e
set -u

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <SSID> <PASSWORD>"
  exit 1
fi

SSID="$1"
PASSWORD="$2"

NETWORK_CONFIG=$(wpa_passphrase "$SSID" "$PASSWORD" | sed '/^#psk=/d')
echo "$NETWORK_CONFIG" >> /etc/wpa_supplicant/wpa_supplicant.conf
