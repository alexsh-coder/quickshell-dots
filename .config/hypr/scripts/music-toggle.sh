#!/usr/bin/env bash
# Super+M: music scratchpad. Pulls any running player into special:music and
# toggles it; if no player is running, launches one (it lands there via rule).
PLAYERS='^(Spotify|ytermusic|feishin|Supersonic|Cider|com.github.th-ch.youtube-music)$'

clients=$(hyprctl clients -j)
addrs=$(jq -r --arg re "$PLAYERS" '.[]
    | select((.class | test($re)) or (.initialTitle | test("^Spotify( Free)?$")))
    | select(.workspace.name != "special:music") | .address' <<<"$clients")
found=$(jq -r --arg re "$PLAYERS" 'any(.[]; (.class | test($re)) or (.initialTitle | test("^Spotify( Free)?$")))' <<<"$clients")

for a in $addrs; do
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:music\", follow = false, window = \"address:$a\" })" >/dev/null
done

if [ "$found" = true ]; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("music")' >/dev/null
elif command -v spotify-launcher >/dev/null; then
    setsid -f spotify-launcher >/dev/null 2>&1
elif [ -x "$HOME/.local/bin/ytermusic" ]; then
    http_proxy=http://127.0.0.1:10809 https_proxy=http://127.0.0.1:10809 \
        setsid -f kitty --class ytermusic -e "$HOME/.local/bin/ytermusic" >/dev/null 2>&1
fi
