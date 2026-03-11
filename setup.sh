#!/bin/bash
# ============================================================
# Perun EEG OSC Streamer - Automatic RPi Setup
# Reads all settings from config.ini
#
# Usage (on the RPi):
#   git clone <repo-url>
#   cd perun-eeg-setup
#   nano config.ini        # edit your settings
#   chmod +x setup.sh
#   ./setup.sh
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.ini"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: config.ini not found in ${SCRIPT_DIR}"
    exit 1
fi

# ---- INI parser ----
ini_get() {
    local section=$1 key=$2
    sed -n "/^\[${section}\]/,/^\[/p" "$CONFIG" | grep "^${key} *=" | head -1 | cut -d= -f2- | sed 's/^ *//;s/ *$//'
}

# ---- Read config ----
DEVICE_NUM=$(ini_get device number)
DEVICE_TYPE=$(ini_get device type)
USB_INDEX=$(ini_get device usb_index)
NEW_HOSTNAME=$(ini_get device hostname)

WIFI_SSID=$(ini_get network wifi_ssid)
WIFI_PSK=$(ini_get network wifi_password)
GATEWAY=$(ini_get network gateway)
STATIC_IP=$(ini_get network static_ip)

PC_IP=$(ini_get osc pc_ip)
OSC_PORT=$(ini_get osc port)
OSC_FPS=$(ini_get osc fps)

SAMPLE_RATE=$(ini_get processing sample_rate)
FFT_WINDOW=$(ini_get processing fft_window)
THETA=$(ini_get processing theta)
ALPHA=$(ini_get processing alpha)
BETA=$(ini_get processing beta)
GAMMA=$(ini_get processing gamma)

CHANNELS=$(ini_get channels active)

# ---- Defaults from device number ----
[ -z "$STATIC_IP" ] && STATIC_IP="192.168.1.5${DEVICE_NUM}"
[ -z "$OSC_PORT" ]  && OSC_PORT="788${DEVICE_NUM}"
[ -z "$OSC_FPS" ]   && OSC_FPS=15
[ -z "$SAMPLE_RATE" ] && SAMPLE_RATE=500
[ -z "$FFT_WINDOW" ] && FFT_WINDOW=1.0
[ -z "$USB_INDEX" ]  && USB_INDEX=0
[ -z "$GATEWAY" ]    && GATEWAY="192.168.1.1"

PERUN_DIR="/home/pi/perun"

echo "============================================"
echo "Perun EEG Streamer Setup - Device #${DEVICE_NUM}"
echo "  Type:       ${DEVICE_TYPE}"
echo "  Static IP:  ${STATIC_IP}"
echo "  OSC target: ${PC_IP}:${OSC_PORT}"
echo "  Channels:   ${CHANNELS}"
echo "  Sample rate: ${SAMPLE_RATE} Hz"
echo "  FFT window: ${FFT_WINDOW}s"
echo "  OSC FPS:    ${OSC_FPS}"
echo "============================================"
echo ""

# ---- 1. Install packages ----
echo "[1/9] Installing packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq g++ make libftdi1-dev python3-pip python3-numpy
sudo pip3 install python-osc --break-system-packages 2>/dev/null || sudo pip3 install python-osc
echo "  Done."

# ---- 2. Set hostname ----
if [ -n "$NEW_HOSTNAME" ]; then
    echo "[2/9] Setting hostname to ${NEW_HOSTNAME}..."
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "  Done."
else
    echo "[2/9] Hostname: keeping $(hostname)"
fi

# ---- 3. Static IP ----
echo "[3/9] Setting static IP ${STATIC_IP}..."
CON_NAME=$(nmcli -t -f NAME,TYPE con show | grep wireless | head -1 | cut -d: -f1)
if [ -z "$CON_NAME" ]; then
    echo "  WARNING: No wireless connection found, skipping static IP."
else
    sudo nmcli con mod "$CON_NAME" ipv4.addresses "${STATIC_IP}/24"
    sudo nmcli con mod "$CON_NAME" ipv4.gateway "${GATEWAY}"
    sudo nmcli con mod "$CON_NAME" ipv4.dns "${GATEWAY} 8.8.8.8"
    sudo nmcli con mod "$CON_NAME" ipv4.method manual
    echo "  Set on connection: ${CON_NAME}"
fi

# ---- 4. Connect WiFi (if SSID provided) ----
if [ -n "$WIFI_SSID" ]; then
    echo "[4/9] WiFi configured for SSID: ${WIFI_SSID}"
else
    echo "[4/9] WiFi: no SSID in config, skipping."
fi

# ---- 5. Disable GUI ----
echo "[5/9] Disabling graphical interface..."
sudo systemctl set-default multi-user.target
echo "  Done."

# ---- 6. Disable Bluetooth ----
echo "[6/9] Disabling Bluetooth..."
sudo systemctl disable bluetooth 2>/dev/null || true
sudo systemctl disable hciuart 2>/dev/null || true
if ! grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt 2>/dev/null; then
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt > /dev/null
fi
echo "  Done."

# ---- 7. Disable WiFi power saving ----
echo "[7/9] Disabling WiFi power saving..."
sudo iw dev wlan0 set power_save off 2>/dev/null || true
cat > /tmp/wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 2
EOF
sudo mv /tmp/wifi-powersave.conf /etc/NetworkManager/conf.d/wifi-powersave.conf
echo "  Done."

# ---- 8. FTDI udev rules + blacklist ftdi_sio ----
echo "[8/9] Configuring FTDI USB rules..."
echo "blacklist ftdi_sio" | sudo tee /etc/modprobe.d/blacklist-ftdi.conf > /dev/null
sudo rmmod ftdi_sio 2>/dev/null || true
sudo bash -c 'cat > /etc/udev/rules.d/99-perun.rules << RULES
SUBSYSTEM=="usb", DRIVER=="usb", ATTR{manufacturer}=="FTDI", ATTRS{product}=="Single RS232-HS", MODE="0666"
SUBSYSTEM=="usb", DRIVER=="usb", ATTR{manufacturer}=="FTDI", ATTRS{product}=="USB <-> Serial Converter", MODE="0666"
RULES'
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "  Done."

# ---- 9. Build, deploy, and create service ----
echo "[9/9] Building perun_reader and deploying streamer..."
mkdir -p "${PERUN_DIR}"

# Copy source files
if [ "$(realpath "$SCRIPT_DIR")" != "$(realpath "$PERUN_DIR")" ]; then
    cp -r "${SCRIPT_DIR}/src" "${PERUN_DIR}/"
    cp "${SCRIPT_DIR}/perun_reader.cpp" "${PERUN_DIR}/"
    cp "${SCRIPT_DIR}/Makefile" "${PERUN_DIR}/"
    cp "${SCRIPT_DIR}/config.ini" "${PERUN_DIR}/"
    cp "${SCRIPT_DIR}/eeg_osc_streamer.py" "${PERUN_DIR}/"
fi

# Build C++ reader
cd "${PERUN_DIR}"
make clean 2>/dev/null || true
make
echo "  Build successful."

# Create USB reset script
cat > "${PERUN_DIR}/reset_usb.sh" << 'RESETSCRIPT'
#!/bin/bash
FTDI_PATH=$(grep -rl '0403' /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1 | sed 's|/idVendor||')
if [ -n "$FTDI_PATH" ]; then
    AUTH="$FTDI_PATH/authorized"
    sudo sh -c "echo 0 > $AUTH && sleep 1 && echo 1 > $AUTH"
    echo "FTDI USB reset done ($FTDI_PATH)"
else
    echo "No FTDI device found, skipping reset"
fi
RESETSCRIPT
chmod +x "${PERUN_DIR}/reset_usb.sh"

# Create systemd service
sudo bash -c "cat > /etc/systemd/system/eeg-streamer.service << SERVICE
[Unit]
Description=EEG Band Power OSC Streamer (${DEVICE_TYPE}) - Device #${DEVICE_NUM}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${PERUN_DIR}
ExecStartPre=/bin/sleep 5
ExecStartPre=${PERUN_DIR}/reset_usb.sh
ExecStart=/usr/bin/python3 -u ${PERUN_DIR}/eeg_osc_streamer.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE"

sudo systemctl daemon-reload
sudo systemctl enable eeg-streamer.service
echo "  Service created and enabled."

echo ""
echo "============================================"
echo "Setup complete for Device #${DEVICE_NUM}!"
echo ""
echo "  Hostname:    $(hostname)"
echo "  Static IP:   ${STATIC_IP} (active after reboot)"
echo "  OSC target:  ${PC_IP}:${OSC_PORT}"
echo "  Channels:    ${CHANNELS}"
echo "  OSC address: /eeg/${DEVICE_NUM}/theta|alpha|beta|gamma"
echo "  Service:     eeg-streamer (enabled, starts on boot)"
echo ""
echo "Commands:"
echo "  sudo systemctl start eeg-streamer   # start now"
echo "  sudo systemctl status eeg-streamer  # check status"
echo "  sudo journalctl -u eeg-streamer -f  # live logs"
echo ""
echo "Reboot now to apply all changes:"
echo "  sudo reboot"
echo "============================================"
