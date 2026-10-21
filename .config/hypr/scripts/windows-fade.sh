#!/usr/bin/env bash
# Fades every window out ("hide") or back in ("show") using Hyprland's own fade animation.
# Active, inactive and fullscreen opacity are separate props, so all three are set.
# Windows with an opacity window_rule get those values back instead of 1.
case "$1" in
    hide|show) ;;
    *) exit 1 ;;
esac

hyprctl eval '
local hide = "'"$1"'" == "hide"
for _, w in ipairs(hl.get_windows()) do
    local a, i, f = "1", "1", "1"
    if hide then
        a, i, f = "0", "0", "0"
    elseif w.class == "Spotify" or w.class == "Happ" then
        a, i = "0.92", "0.85"
    end
    local win = "address:" .. w.address
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = a, window = win }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = i, window = win }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_fullscreen", value = f, window = win }))
end' >/dev/null
