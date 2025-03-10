# RPIHID
My trial to make raspberry pi zero keyboard that might be helpful in sending keystrokes


dependcies
- enable HID USB support in RaspberryPi
- install flask
- python3


Edit /boot/config.txt:
Add the following line to enable the DWC2 overlay:
```bash
dtoverlay=dwc2
```
Modify /boot/cmdline.txt:
In the same file, after rootwait, insert (on the same line) the following parameter:
```bash
modules-load=dwc2
```
Be sure not to break the one‑line structure of this file.


1. Create a Systemd Service File
Create a new file called /etc/systemd/system/flask-hid.service with the following content:

```ini
[Unit]
Description=Flask HID Keyboard Service
After=network.target

[Service]
# Run as the pi user (or another appropriate user).
User=pi
Group=pi
WorkingDirectory=/usr/local/bin
# Adjust the path to your Python interpreter and app.py location.
ExecStart=/usr/bin/python3 /usr/local/bin/app.py
Restart=always
# Optionally set environment variables if needed
# Environment="FLASK_APP=app.py"

[Install]
WantedBy=multi-user.target
```
Notes:

User/Group: Make sure the specified user (e.g., pi) has access to /dev/hidg0. If not, either run as root or adjust udev rules accordingly.
WorkingDirectory: Change /home/pi/hid_flask to the folder where your app.py and templates reside.
ExecStart: Verify that /usr/bin/python3 is the correct path to your Python interpreter.
2. Reload systemd and Enable the Service
After saving the service file, reload systemd and enable/start your new service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable flask-hid.service
sudo systemctl start flask-hid.service
```
To check the service status:

```bash
sudo systemctl status flask-hid.service
```
This command should indicate that your Flask HID keyboard service is running.

