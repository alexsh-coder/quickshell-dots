#!/usr/bin/env bash
# Screenshot -> clipboard + ~/Pictures/Screenshots.
#   screenshot.sh         click a window or drag a region, over a frozen screen
#   screenshot.sh screen  the focused monitor
# hyprpicker -r -z only draws a still frame of every output (same trick as
# grimblast --freeze); grim shoots that frame, so the result matches what was selected.
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
out="$dir/$(date +%Y%m%d-%H%M%S).png"

if [[ $1 == screen ]]; then
    mon=$(hyprctl -j monitors | jq -r '.[] | select(.focused).name')
    grim -o "$mon" - | tee "$out" | wl-copy
    exit
fi

hyprpicker -r -z -d -q &
freeze=$!
trap 'kill "$freeze" 2>/dev/null' EXIT
sleep 0.15

geom=$("${0%/*}/window-boxes.sh" | slurp) || exit 1
grim -g "$geom" - | tee "$out" | wl-copy
