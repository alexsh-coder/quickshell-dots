#!/bin/sh
# Move to the adjacent workspace, but refuse to leave the current one
# empty-handed onto another empty workspace (avoids stacking empty
# workspaces and the waybar indicator flicker that causes).
dir="$1"

# Only the "+1" (rightward) direction can create a brand new empty
# workspace. Moving left never creates one, so only block "+1" when
# already on an empty workspace.
if [ "$dir" = "+1" ]; then
    windows=$(hyprctl activeworkspace | grep -oP '(?<=windows: )\d+')
    if [ "${windows:-0}" -eq 0 ]; then
        exit 0
    fi
fi

hyprctl dispatch 'hl.dsp.focus({ workspace = "'"$dir"'" })' >/dev/null
