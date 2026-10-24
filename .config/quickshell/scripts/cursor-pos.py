#!/usr/bin/env python3
"""Prints the pointer position ("x y", layout coords) each time it changes, polling Hyprland's socket."""
import os
import socket
import sys
import time

path = f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket.sock"
last = None
# Fast while the pointer moves, about once a frame while it rests: Hyprland answers every poll
FAST, SLOW, SETTLE = 0.004, 0.016, 0.5
moved = 0.0
while True:
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.connect(path)
            s.sendall(b"cursorpos")
            pos = s.recv(64).decode().replace(",", "")
        if pos != last:
            last = pos
            moved = time.monotonic()
            sys.stdout.write(pos + "\n")
            sys.stdout.flush()
    except (OSError, ValueError):
        time.sleep(1)
    time.sleep(FAST if time.monotonic() - moved < SETTLE else SLOW)
