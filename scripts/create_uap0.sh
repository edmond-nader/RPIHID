#!/usr/bin/env bash
# create_uap0.sh
# Create a virtual interface uap0 for AP mode if it does not exist, then bring it up.
set -e

if ip link show uap0 >/dev/null 2>&1; then
    echo "Interface uap0 already exists."
else
    echo "Creating virtual interface uap0 on wlan0..."
    iw dev wlan0 interface add uap0 type __ap
fi

ip link set uap0 up
echo "Interface uap0 is up."
