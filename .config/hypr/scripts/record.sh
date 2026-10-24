#!/usr/bin/env bash
# Screen recording toggle -> ~/Videos/Screencasts, with desktop audio.
#   record.sh         click a window or drag a region
#   record.sh screen  the focused monitor, as 8-bit H.264 that Reddit takes as is
# Running it again while recording stops and saves.
pkill -INT -x gpu-screen-reco && exit

dir="$HOME/Videos/Screencasts"
mkdir -p "$dir"
out="$dir/$(date +%Y%m%d-%H%M%S).mp4"

# hevc_10bit + constant QP avoids banding on blur and gradients
codec=hevc_10bit
if [[ $1 == screen ]]; then
    target=(-w "$(hyprctl -j monitors | jq -r '.[] | select(.focused).name')")
    codec=h264
else
    geom=$("${0%/*}/window-boxes.sh" | slurp -f '%wx%h+%x+%y') || exit 1
    target=(-w region -region "$geom")
fi

# The bar shows a recording indicator between these two calls
# Flatpak build bundles an FFmpeg that matches the legacy NVIDIA driver
gsr=(gpu-screen-recorder)
flatpak info com.dec05eba.gpu_screen_recorder &>/dev/null &&
    gsr=(flatpak run --command=gpu-screen-recorder com.dec05eba.gpu_screen_recorder)

"${gsr[@]}" "${target[@]}" -f 60 -fm cfr -k "$codec" -bm qp -q ultra -a default_output -ac aac -ab 256 -o "$out" &
pid=$!
qs ipc call recorder started >/dev/null 2>&1
wait "$pid"
rc=$?
qs ipc call recorder stopped >/dev/null 2>&1
if [[ -s $out ]]; then
    notify-send -a "Screen recorder" "Recording saved" "${out/#$HOME/\~}"
else
    notify-send -u critical -a "Screen recorder" "Recording failed" "exit code $rc"
fi
