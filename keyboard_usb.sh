#!/bin/bash
GADGET_DIR="/sys/kernel/config/usb_gadget/g1"

# Unbind the gadget first.
if [ -f "$GADGET_DIR/UDC" ]; then
    echo "" > "$GADGET_DIR/UDC"
fi

# Remove old gadget configuration (ignore errors for read-only files)
if [ -d "$GADGET_DIR" ]; then
    rm -rf "$GADGET_DIR" 2>/dev/null
fi

# Create the gadget directory.
mkdir -p $GADGET_DIR
cd $GADGET_DIR

# Basic gadget configuration.
echo 0x1d6b > idVendor   # Linux Foundation
echo 0x0104 > idProduct  # Multifunction Composite Gadget
echo 0x0100 > bcdDevice  # v1.0.0
echo 0x0200 > bcdUSB     # USB 2.0

# Set up English strings.
mkdir -p strings/0x409
echo "0123456789" > strings/0x409/serialnumber
echo "MyCompany" > strings/0x409/manufacturer
echo "RPi HID Keyboard" > strings/0x409/product

# Create configuration.
mkdir -p configs/c.1
mkdir -p configs/c.1/strings/0x409
echo "Config 1: HID Keyboard" > configs/c.1/strings/0x409/configuration
echo 120 > configs/c.1/MaxPower

# Create HID function for keyboard.
mkdir -p functions/hid.usb0
echo 8 > functions/hid.usb0/report_length
# Standard keyboard report descriptor (8 bytes)
echo -ne "\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\xc0" > functions/hid.usb0/report_desc

# Bind the HID function to configuration.
ln -s functions/hid.usb0 configs/c.1/

# Enable the gadget: find UDC.
UDC=$(ls /sys/class/udc | head -n 1)
echo $UDC > UDC

echo "Keyboard gadget configured successfully."
