#!/usr/bin/env bash
# Lock with the Quickshell lockscreen; fall back to hyprlock when the shell isn't running.
qs ipc call lock lock 2>/dev/null && exit 0
link="$HOME/.cache/hyprlock-bg"
img=$(awww query 2>/dev/null | sed -n '1s/.*currently displaying: image: //p')
[ -f "$img" ] && ln -sfn "$img" "$link"
pidof hyprlock >/dev/null || exec hyprlock
