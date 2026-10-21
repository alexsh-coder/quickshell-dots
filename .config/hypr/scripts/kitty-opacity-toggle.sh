#!/usr/bin/env bash
# Toggles background opacity for the currently focused kitty window only,
# between the transparent "pretty" look (0.82) and a fully solid background.
#
# kitty always suffixes its abstract remote-control socket with "-<pid>"
# (see `listen_on` docs), so we target that specific process's socket.
# `set-background-opacity` without --all only affects that process's
# currently active OS window, which keeps the change local to the
# terminal that was focused when the key was pressed.

STATE_DIR="/tmp/kitty-opacity-state"
TRANSPARENT=0.82

ACTIVE_JSON="$(hyprctl activewindow -j)"
CLASS="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("class",""))' <<<"$ACTIVE_JSON")"
PID="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("pid",""))' <<<"$ACTIVE_JSON")"

if [[ "$CLASS" != "kitty" || -z "$PID" ]]; then
    exit 0
fi

mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$PID"

if [[ "$(cat "$STATE_FILE" 2>/dev/null)" == "solid" ]]; then
    NEW="$TRANSPARENT"
    echo "transparent" > "$STATE_FILE"
else
    NEW="1.0"
    echo "solid" > "$STATE_FILE"
fi

kitty @ --to "unix:@kitty-$PID" set-background-opacity "$NEW" 2>/dev/null
