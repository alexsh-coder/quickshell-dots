#!/usr/bin/env bash
# Visible windows as slurp boxes ("x,y wxh"), clipped to their monitor, topmost first.
# Feed to slurp's stdin: click a box to pick a window, drag for a free region.
jq -rn --argjson mons "$(hyprctl -j monitors)" --argjson clients "$(hyprctl -j clients)" '
  [ $mons[] | . as $m
    | (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end
       | map(. / $m.scale | floor)) as [$mw, $mh]
    | $clients[]
    | select(.mapped and (.hidden | not))
    | select(.workspace.id == $m.activeWorkspace.id or .workspace.id == $m.specialWorkspace.id)
    | [ ([.at[0], $m.x] | max), ([.at[1], $m.y] | max),
        ([.at[0] + .size[0], $m.x + $mw] | min), ([.at[1] + .size[1], $m.y + $mh] | min),
        (if .floating then 0 else 1 end), .focusHistoryID ]
    | select(.[2] > .[0] and .[3] > .[1]) ]
  | sort_by(.[4], .[5])[]
  | "\(.[0]),\(.[1]) \(.[2] - .[0])x\(.[3] - .[1])"'
