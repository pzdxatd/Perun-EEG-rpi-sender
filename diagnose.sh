#!/bin/bash
# ============================================================
# Perun EEG OSC Streamer - diagnostics
# Run on the RPi:   bash diagnose.sh
# Collects everything needed to figure out why OSC isn't flowing.
# ============================================================

line() { echo; echo "==== $* ===="; }

line "hostname / uptime"
hostname
uptime

line "IP addresses"
ip -4 -o addr
echo "--- default route ---"
ip route | grep default || echo "(no default route)"

line "NetworkManager connections"
nmcli -t -f NAME,DEVICE,STATE,TYPE con show || true
echo "--- active only ---"
nmcli -t -f NAME,DEVICE,STATE,TYPE con show --active || true

line "wlan0 link + signal"
iw dev wlan0 link 2>/dev/null || echo "(iw not installed or no wlan0)"

line "DNS / ping gateway"
GW=$(ip route | awk '/default/ {print $3; exit}')
if [ -n "$GW" ]; then
    ping -c 2 -W 1 "$GW" || echo "(gateway unreachable)"
fi

line "ping PC (OSC target from config.ini)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PC_IP=$(sed -n '/^\[osc\]/,/^\[/p' "${SCRIPT_DIR}/config.ini" 2>/dev/null \
        | grep '^pc_ip' | head -1 | cut -d= -f2- | tr -d ' ')
if [ -z "$PC_IP" ]; then
    PC_IP=$(sed -n '/^\[osc\]/,/^\[/p' /home/pi/perun/config.ini 2>/dev/null \
            | grep '^pc_ip' | head -1 | cut -d= -f2- | tr -d ' ')
fi
if [ -n "$PC_IP" ]; then
    echo "PC target: $PC_IP"
    ping -c 2 -W 1 "$PC_IP" || echo "(PC unreachable — OSC packets will go nowhere)"
else
    echo "(could not read pc_ip from config.ini)"
fi

line "FTDI USB presence"
lsusb | grep -i ftdi || echo "(no FTDI device on USB — perun_reader will block)"
ls /sys/bus/usb/devices/*/idVendor 2>/dev/null | while read f; do
    v=$(cat "$f"); [ "$v" = "0403" ] && echo "  FTDI at: $(dirname $f)"
done
lsmod | grep ftdi_sio && echo "  WARNING: ftdi_sio kernel module loaded (should be blacklisted)"

line "perun_reader binary"
ls -la /home/pi/perun/perun_reader 2>/dev/null || echo "(binary missing — setup.sh [9/9] failed?)"

line "eeg-streamer service status"
sudo systemctl status eeg-streamer --no-pager -l 2>&1 | head -30

line "eeg-streamer journal (this boot)"
sudo journalctl -u eeg-streamer -b --no-pager 2>&1 | tail -60

line "eeg-streamer journal (previous boot, if persistent)"
sudo journalctl -u eeg-streamer -b -1 --no-pager 2>&1 | tail -30

line "DONE"
echo "Copy-paste the full output when asking for help."
