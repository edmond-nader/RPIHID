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
cat << 'EOF' > ${HID_SCRIPT_PATH}
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
EOF

chmod +x ${HID_SCRIPT_PATH}

# 3. Create the systemd service unit file.
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

# 4. Reload systemd daemon and enable the service.
systemctl daemon-reload
systemctl enable usb-gadget.service

echo "Setup complete. Please reboot your system for changes to take effect."
