#!/usr/bin/env bash
# Screen recording toggle -> ~/Videos/Screencasts, with desktop audio.
#   record.sh         click a window or drag a region
#   record.sh screen  the focused monitor
# Running it again while recording stops and saves.
pkill -INT -f '^gpu-screen-recorder ' && exit

dir="$HOME/Videos/Screencasts"
mkdir -p "$dir"
out="$dir/$(date +%Y%m%d-%H%M%S).mp4"

if [[ $1 == screen ]]; then
    target=(-w "$(hyprctl -j monitors | jq -r '.[] | select(.focused).name')")
else
    geom=$("${0%/*}/window-boxes.sh" | slurp -f '%wx%h+%x+%y') || exit 1
    target=(-w region -region "$geom")
fi

# The bar shows a recording indicator between these two calls
gpu-screen-recorder "${target[@]}" -f 60 -a default_output -ac aac -o "$out" &
pid=$!
qs ipc call recorder started >/dev/null 2>&1
wait "$pid"
rc=$?
qs ipc call recorder stopped >/dev/null 2>&1
((rc == 0)) && notify-send -a "Screen recorder" "Recording saved" "${out/#$HOME/\~}"
