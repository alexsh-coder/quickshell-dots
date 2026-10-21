#!/usr/bin/env bash
# Toggle the night-light warmth via hyprsunset.
# Usage: night-mode-toggle.sh [toggle|on|off]

set -euo pipefail

command -v hyprsunset >/dev/null || { echo "hyprsunset is not installed" >&2; exit 1; }

TEMP=4000
STATE="$XDG_RUNTIME_DIR/hyprsunset-night-light"

current=off
if [[ "$(cat "$STATE" 2>/dev/null)" == on ]]; then
    current=on
fi

case "${1:-toggle}" in
    on)
        want=on
        ;;
    off)
        want=off
        ;;
    toggle)
        if [[ "$current" == on ]]; then want=off; else want=on; fi
        ;;
    *)
        echo "usage: ${0##*/} [toggle|on|off]" >&2
        exit 2
        ;;
esac

# Match only this user's daemon: the machine is shared, and hyprctl talks
# to the socket under our own Hyprland instance signature.
if ! pgrep -x -u "$UID" hyprsunset >/dev/null; then
    setsid hyprsunset --identity >/dev/null 2>&1 &
    sock="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.hyprsunset.sock"
    for _ in {1..40}; do
        [[ -S "$sock" ]] && break
        sleep 0.05
    done
    if [[ ! -S "$sock" ]]; then
        echo "hyprsunset failed to start" >&2
        exit 1
    fi
fi

if [[ "$want" == on ]]; then
    hyprctl hyprsunset temperature "$TEMP" >/dev/null
else
    # identity is a true bypass; 6500K still leaves a slight tint
    hyprctl hyprsunset identity >/dev/null
fi

printf '%s\n' "$want" > "$STATE"

# OSD feedback; the toggle works fine without Quickshell running
qs ipc call osd night "$want" >/dev/null 2>&1 || true
