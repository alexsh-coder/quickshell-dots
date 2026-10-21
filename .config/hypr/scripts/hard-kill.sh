#!/usr/bin/env bash
# Kill the process owning the focused window, not just close the window.
pid=$(hyprctl activewindow -j | jq -r '.pid // empty')
[ -n "$pid" ] && [ "$pid" -gt 1 ] || exit 0
kill -TERM "$pid"
for _ in 1 2 3 4 5; do
    sleep 0.2
    kill -0 "$pid" 2>/dev/null || exit 0
done
kill -KILL "$pid"
