#!/usr/bin/env bash
# create_uap0.sh
# Creates a virtual AP interface (uap0) on wlan0 if it doesn't exist, then brings it up.
# This script sets PATH to include /usr/sbin and /sbin so that 'iw' is found.
set -e

export PATH=$PATH:/usr/sbin:/sbin

if ip link show uap0 >/dev/null 2>&1; then
    echo "Interface uap0 already exists."
else
    echo "Creating virtual interface uap0 on wlan0..."
    iw dev wlan0 interface add uap0 type __ap || { echo "Failed to create uap0 interface"; exit 1; }
fi

ip link set uap0 up
echo "Interface uap0 is up."
