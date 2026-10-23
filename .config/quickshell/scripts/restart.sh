#!/usr/bin/env bash
# Restarts Quickshell the way hyprland.lua starts it, at panel scale SCALE.
# Usage: restart.sh PID SCALE
set -u

pid=$1
scale=${2:-1}

# The respawn loop would bring it back at the old scale, next to the one started below
pkill -f '^bash .*/respawn\.sh env QSG_RENDER_LOOP=[^ ]* QT_SCALE_FACTOR=[^ ]* qs$'
kill -TERM "$pid" 2>/dev/null
for _ in $(seq 100); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
done
hyprctl dispatch "hl.dsp.exec_cmd(\"~/.config/hypr/scripts/respawn.sh env QSG_RENDER_LOOP=threaded QT_SCALE_FACTOR=$scale qs\")"
