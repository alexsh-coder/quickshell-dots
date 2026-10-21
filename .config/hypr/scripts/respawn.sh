#!/usr/bin/env bash
# Keep a session daemon alive: restart it if it exits/crashes, stop once
# Hyprland is gone (its IPC socket disappears). Works without uwsm/systemd.
# Usage: respawn.sh <command> [args...]
command -v "$1" >/dev/null || exit 0   # not installed on this machine
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock"
while [ -S "$sock" ]; do
    "$@"
    sleep 1
done
