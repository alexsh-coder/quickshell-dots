#!/usr/bin/env bash
# Screenshot -> clipboard + ~/Pictures/Screenshots.
#   screenshot.sh         click a window or drag a region, over a frozen screen (Quickshell picker)
#   screenshot.sh screen  the focused monitor
# hyprpicker -r -z only draws a still frame of every output (same trick as
# grimblast --freeze); grim shoots that frame, so the result matches what was selected.
# One at a time: a second press while selecting is ignored.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/screenshot.lock"
flock -n 9 || exit 0

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
out="$dir/$(date +%Y%m%d-%H%M%S).png"

if [[ $1 == screen ]]; then
    mon=$(hyprctl -j monitors | jq -r '.[] | select(.focused).name')
    grim -o "$mon" - | tee "$out" | wl-copy 9>&-
    exit
fi

hyprpicker -r -z -d -q 9>&- &
freeze=$!
trap 'kill "$freeze" 2>/dev/null' EXIT
sleep 0.15

# Pick in Quickshell's picker (modules/screenshot), which answers through a file
res="${XDG_RUNTIME_DIR:-/tmp}/screenshot.pick"
rm -f "$res"
qs ipc call screenshot pick "$res" "$("${0%/*}/window-boxes.sh")" >/dev/null || exit 1
# Gives up once the picker is gone without answering (qs reloaded or crashed)
n=0
until [[ -e $res ]]; do
    sleep 0.03
    (( ++n % 15 )) || hyprctl layers | grep -q "namespace: screenshot" || { sleep 0.2; [[ -e $res ]] || exit 1; }
done
geom=$(<"$res")
rm -f "$res"
[[ -n $geom ]] || exit 1
grim -g "$geom" - | tee "$out" | wl-copy 9>&-
