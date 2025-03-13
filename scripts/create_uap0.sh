#!/usr/bin/env bash
# create_uap0.sh
# Creates a virtual AP interface (uap0) on wlan0 if it doesn't exist,
# brings it up, and assigns a static IP address (192.168.4.1/24) if not already present.
set -e

# Ensure PATH includes directories where iw, ip, etc. are located.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create uap0 if it doesn't exist.
if ip link show uap0 >/dev/null 2>&1; then
    echo "Interface uap0 already exists."
else
    echo "Creating virtual interface uap0 on wlan0..."
    iw dev wlan0 interface add uap0 type __ap || { echo "Failed to create uap0 interface"; exit 1; }
fi

# Bring the interface up.
ip link set uap0 up

# Assign static IP if not already present.
if ! ip addr show uap0 | grep -q "192.168.4.1/24"; then
    echo "Assigning static IP 192.168.4.1/24 to uap0..."
    ip addr add 192.168.4.1/24 dev uap0 || true
fi

echo "Interface uap0 is up with the following configuration:"
ip addr show uap0
