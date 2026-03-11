#!/bin/bash
# ============================================================
# Deploy perun-eeg-setup to an RPi from your PC
# Reads deploy settings from config.ini
#
# Usage: ./deploy.sh <PI_CURRENT_IP>
#   e.g. ./deploy.sh 192.168.1.107
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.ini"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: config.ini not found"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <PI_CURRENT_IP>"
    echo "  e.g. ./deploy.sh 192.168.1.107"
    echo ""
    echo "  Reads device number, SSH key, and user from config.ini"
    exit 1
fi

# INI parser
ini_get() {
    local section=$1 key=$2
    sed -n "/^\[${section}\]/,/^\[/p" "$CONFIG" | grep "^${key} *=" | head -1 | cut -d= -f2- | sed 's/^ *//;s/ *$//'
}

PI_IP=$1
DEVICE_NUM=$(ini_get device number)
SSH_USER=$(ini_get deploy ssh_user)
SSH_KEY=$(ini_get deploy ssh_key)

[ -z "$SSH_USER" ] && SSH_USER="pi"

SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="${SSH_OPTS} -i ${SSH_KEY}"
fi

echo "Deploying to ${SSH_USER}@${PI_IP} as Device #${DEVICE_NUM}..."
[ -n "$SSH_KEY" ] && echo "Using SSH key: ${SSH_KEY}"
echo ""

# Test connection
ssh ${SSH_OPTS} ${SSH_USER}@${PI_IP} "echo 'Connected to \$(hostname)'" || {
    echo "ERROR: Cannot SSH to ${SSH_USER}@${PI_IP}"
    exit 1
}

# Create target directory
ssh ${SSH_OPTS} ${SSH_USER}@${PI_IP} "mkdir -p /home/pi/perun/src/perun/lib"

# Copy all files
echo "Copying files..."
scp ${SSH_OPTS} -r "${SCRIPT_DIR}/src/"* ${SSH_USER}@${PI_IP}:/home/pi/perun/src/
scp ${SSH_OPTS} \
    "${SCRIPT_DIR}/perun_reader.cpp" \
    "${SCRIPT_DIR}/Makefile" \
    "${SCRIPT_DIR}/eeg_osc_streamer.py" \
    "${SCRIPT_DIR}/setup.sh" \
    "${SCRIPT_DIR}/config.ini" \
    ${SSH_USER}@${PI_IP}:/home/pi/perun/

ssh ${SSH_OPTS} ${SSH_USER}@${PI_IP} "chmod +x /home/pi/perun/setup.sh"

# Run setup
echo "Running setup on the Pi..."
ssh ${SSH_OPTS} ${SSH_USER}@${PI_IP} "cd /home/pi/perun && ./setup.sh"

STATIC_IP=$(ini_get network static_ip)
[ -z "$STATIC_IP" ] && STATIC_IP="192.168.1.5${DEVICE_NUM}"

echo ""
echo "Deploy complete! Reboot the Pi to apply all changes:"
echo "  ssh ${SSH_OPTS} ${SSH_USER}@${PI_IP} 'sudo reboot'"
echo ""
echo "After reboot, Pi will be at ${STATIC_IP}"
