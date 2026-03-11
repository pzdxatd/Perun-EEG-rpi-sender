# Perun EEG OSC Streamer

Streams EEG band powers (theta, alpha, beta, gamma) from a BrainTech Perun 8 wireless headset to a PC via OSC over WiFi. Runs on Raspberry Pi (Zero 2W, RPi 4, etc.).

## Architecture

```
Perun 8 headset → FTDI USB dongle → perun_reader (C++) → stdout CSV
    → eeg_osc_streamer.py → OSC UDP → PC
```

## Quick Start

### Option A: Setup directly on the RPi

```bash
git clone <repo-url>
cd perun-eeg-setup
nano config.ini          # edit your settings
chmod +x setup.sh
./setup.sh
sudo reboot
```

### Option B: Deploy from your PC

```bash
git clone <repo-url>
cd perun-eeg-setup
nano config.ini          # edit your settings
chmod +x deploy.sh
./deploy.sh <PI_CURRENT_IP>
```

## Configuration

All settings are in **`config.ini`**. Edit before running setup.

### `[device]`
| Key | Description | Example |
|-----|-------------|---------|
| `number` | Device number (1-9). Auto-sets IP and port. | `1` |
| `type` | Headset model | `perun8` |
| `usb_index` | FTDI USB device index | `0` |
| `hostname` | RPi hostname (empty = keep current) | `pilsl1` |

### `[network]`
| Key | Description | Example |
|-----|-------------|---------|
| `wifi_ssid` | WiFi network name | `Sound` |
| `wifi_password` | WiFi password | `71241081` |
| `gateway` | Network gateway | `192.168.1.1` |
| `static_ip` | Override auto IP (empty = `192.168.1.5<N>`) | |

### `[osc]`
| Key | Description | Example |
|-----|-------------|---------|
| `pc_ip` | PC IP address (OSC destination) | `192.168.1.23` |
| `port` | Override auto port (empty = `788<N>`) | |
| `fps` | OSC send rate in Hz | `15` |

### `[processing]`
| Key | Description | Example |
|-----|-------------|---------|
| `sample_rate` | Sampling rate in Hz | `500` |
| `fft_window` | FFT window in seconds | `1.0` |
| `theta` | Theta band range (Hz) | `4-8` |
| `alpha` | Alpha band range (Hz) | `8-13` |
| `beta` | Beta band range (Hz) | `13-30` |
| `gamma` | Gamma band range (Hz) | `30-50` |

### `[channels]`
| Key | Description | Example |
|-----|-------------|---------|
| `active` | Active EEG channels (comma-separated) | `P3,Cz,O2,P4,C3,O1,Pz,C4` |

### `[deploy]`
| Key | Description | Example |
|-----|-------------|---------|
| `ssh_key` | Path to SSH private key (empty = password auth) | `~/.ssh/id_pi1` |
| `ssh_user` | SSH username | `pi` |
| `ssh_password` | SSH password (if no key) | `zero1` |

## OSC Output

Each device sends 4 OSC messages per frame:

```
/eeg/<N>/theta   float 0-100
/eeg/<N>/alpha   float 0-100
/eeg/<N>/beta    float 0-100
/eeg/<N>/gamma   float 0-100
```

## Testing on PC

```bash
pip install python-osc
python osc_listener.py 7881    # listen on port 7881
```

## Service Commands

```bash
sudo systemctl start eeg-streamer    # start
sudo systemctl stop eeg-streamer     # stop
sudo systemctl status eeg-streamer   # status
sudo journalctl -u eeg-streamer -f   # live logs
```

## Files

| File | Description |
|------|-------------|
| `config.ini` | All settings (edit this first) |
| `setup.sh` | RPi setup script (reads config.ini) |
| `deploy.sh` | Remote deploy from PC (reads config.ini) |
| `eeg_osc_streamer.py` | Python streamer (reads config.ini at runtime) |
| `perun_reader.cpp` | C++ EEG reader (stdout CSV) |
| `Makefile` | Builds perun_reader |
| `src/` | Perun SDK sources |
| `osc_listener.py` | PC-side test listener |
