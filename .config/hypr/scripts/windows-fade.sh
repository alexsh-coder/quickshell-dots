#!/usr/bin/env bash
# Fades every window out ("hide") or back in ("show") using Hyprland's own fade animation.
# Windows with an opacity window_rule get that value back instead of 1.
case "$1" in
    hide) v=0 ;;
    show) v=1 ;;
    *) exit 1 ;;
esac

hyprctl eval '
for _, w in ipairs(hl.get_windows()) do
    local v = "'"$v"'"
    if v == "1" and (w.class == "Spotify" or w.class == "Happ") then v = "0.92" end
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = v, window = "address:" .. w.address }))
end' >/dev/null
