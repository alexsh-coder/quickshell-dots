#!/usr/bin/env bash
# Restarts Quickshell the way hyprland.lua starts it, at panel scale SCALE.
# Usage: restart.sh PID SCALE
set -u

pid=$1
scale=${2:-1}

kill -TERM "$pid" 2>/dev/null
for _ in $(seq 100); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
done
# The crash handler may have brought it back by itself
sleep 0.5
qs list --all 2>/dev/null | grep -q 'Process ID' && exit 0
hyprctl dispatch "hl.dsp.exec_cmd(\"env QSG_RENDER_LOOP=threaded QT_SCALE_FACTOR=$scale qs\")"
