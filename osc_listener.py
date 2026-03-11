#!/usr/bin/env python3
"""
PC-side OSC listener for testing EEG band power reception.
Listens on all ports (7881-7889) or a specific port via argument.

Usage:
  python osc_listener.py          # listens on port 7881
  python osc_listener.py 7883     # listens on port 7883
"""
from pythonosc import dispatcher, osc_server
import sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 7881

def handler(addr, *args):
    vals = [f"{v:.1f}" for v in args]
    print(f"{addr}: [{', '.join(vals[:8])}]{'...' if len(vals) > 8 else ''}")

d = dispatcher.Dispatcher()
d.set_default_handler(handler)
server = osc_server.ThreadingOSCUDPServer(("0.0.0.0", port), d)
print(f"Listening for OSC on port {port}...")
try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\nDone.")
