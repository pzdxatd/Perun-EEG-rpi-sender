#!/usr/bin/env python3
"""
EEG Band Power OSC Streamer for Perun headsets.
All settings are read from config.ini at startup.
"""

import configparser
import os
import subprocess
import sys
import time
import numpy as np
from collections import deque
from pythonosc import udp_client

# ---- Load config ----
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.ini")

cfg = configparser.ConfigParser()
cfg.read(CONFIG_PATH)

DEVICE_NUM   = cfg.getint("device", "number")
DEVICE_TYPE  = cfg.get("device", "type", fallback="perun8")
USB_INDEX    = cfg.getint("device", "usb_index", fallback=0)

PC_IP        = cfg.get("osc", "pc_ip")
OSC_PORT     = cfg.getint("osc", "port", fallback=0) or (7880 + DEVICE_NUM)
OSC_FPS      = cfg.getint("osc", "fps", fallback=15)

SAMPLE_RATE  = cfg.getint("processing", "sample_rate", fallback=500)
FFT_WINDOW   = cfg.getfloat("processing", "fft_window", fallback=1.0)
WINDOW_SAMPLES = int(SAMPLE_RATE * FFT_WINDOW)

# Parse channels
CHANNELS = [ch.strip() for ch in cfg.get("channels", "active").split(",")]
NUM_CH = len(CHANNELS)

# Parse bands (format: "4-8")
def parse_band(val):
    lo, hi = val.split("-")
    return (float(lo), float(hi))

BANDS = {}
for band_name in ["theta", "alpha", "beta", "gamma"]:
    raw = cfg.get("processing", band_name, fallback=None)
    if raw:
        BANDS[band_name] = parse_band(raw)

# Defaults if missing
if not BANDS:
    BANDS = {"theta": (4, 8), "alpha": (8, 13), "beta": (13, 30), "gamma": (30, 50)}


def compute_band_powers(buffer, fs):
    """Compute band powers averaged across all channels. Returns dict of band -> float 0-100."""
    n = buffer.shape[0]
    if n < 32:
        return None

    window = np.hanning(n)
    freqs = np.fft.rfftfreq(n, 1.0 / fs)

    powers = {}
    for band_name, (flo, fhi) in BANDS.items():
        idx = np.where((freqs >= flo) & (freqs <= fhi))[0]
        if len(idx) == 0:
            powers[band_name] = 0.0
            continue

        band_power = 0.0
        for ch in range(NUM_CH):
            signal = buffer[:, ch] - np.mean(buffer[:, ch])
            spectrum = np.abs(np.fft.rfft(signal * window)) ** 2
            band_power += np.mean(spectrum[idx])
        band_power /= NUM_CH

        bp = np.log10(band_power + 1e-10)
        bp = np.clip((bp / 14.0) * 100.0, 0, 100)
        powers[band_name] = float(bp)

    return powers


def main():
    print(f"EEG OSC Streamer - Device #{DEVICE_NUM} ({DEVICE_TYPE})")
    print(f"Sending to {PC_IP}:{OSC_PORT} at ~{OSC_FPS} fps")
    print(f"FFT window: {FFT_WINDOW}s ({WINDOW_SAMPLES} samples)")
    print(f"Channels ({NUM_CH}): {', '.join(CHANNELS)}")
    print(f"Bands: {', '.join(f'{k} {v[0]}-{v[1]}Hz' for k, v in BANDS.items())}")

    osc = udp_client.SimpleUDPClient(PC_IP, OSC_PORT)

    reader_path = os.path.join(SCRIPT_DIR, "perun_reader")
    print(f"Starting {reader_path} (usb_index={USB_INDEX})...")
    proc = subprocess.Popen(
        [reader_path, str(USB_INDEX)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1
    )

    buffer = deque(maxlen=WINDOW_SAMPLES)
    osc_interval = 1.0 / OSC_FPS
    last_osc_time = 0
    samples_received = 0
    start_time = time.time()

    try:
        for line in proc.stdout:
            line = line.strip()
            if not line or line.startswith(CHANNELS[0]):
                continue

            try:
                values = [float(x) for x in line.split(",")]
            except ValueError:
                continue

            if len(values) != NUM_CH:
                continue

            buffer.append(values)
            samples_received += 1

            now = time.time()
            if now - last_osc_time >= osc_interval and len(buffer) >= 64:
                last_osc_time = now
                arr = np.array(buffer)
                powers = compute_band_powers(arr, SAMPLE_RATE)
                if powers is None:
                    continue

                for band_name, val in powers.items():
                    osc.send_message(f"/eeg/{DEVICE_NUM}/{band_name}", val)

                elapsed = now - start_time
                if samples_received % (SAMPLE_RATE * 5) < SAMPLE_RATE // OSC_FPS:
                    rate = samples_received / elapsed if elapsed > 0 else 0
                    print(f"[{elapsed:.0f}s] rate: {rate:.0f} Hz, "
                          f"t:{powers['theta']:.1f} a:{powers['alpha']:.1f} "
                          f"b:{powers['beta']:.1f} g:{powers['gamma']:.1f}")

    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        proc.terminate()
        proc.wait(timeout=5)
        print("Done.")


if __name__ == "__main__":
    main()
