#!/usr/bin/env bash
# wifi_fallback.sh
# Wait 30 seconds after boot and start hotspot mode if no Wi‑Fi connection exists.

sleep 30

if ! /sbin/ip addr show wlan0 | grep -q "inet "; then
    echo "Wi‑Fi not connected – starting hotspot mode..."
    sudo systemctl stop wpa_supplicant
    sudo ifconfig wlan0 down
    sudo ifconfig wlan0 up
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
else
    echo "Wi‑Fi connected – hotspot not required."
    sudo systemctl stop hostapd || true
    sudo systemctl stop dnsmasq || true
fi
