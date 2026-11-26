#!/usr/bin/env python3
"""Move every window on the current workspace (or workspace argv[2]) to
workspace argv[1], keeping the dwindle layout.

dwindle inserts a moved window by splitting an existing one (the focused one,
side picked by cursor position), so moving windows one by one in creation order
shuffles them. Instead we recover the split tree from window geometry
(guillotine cuts) and replay it: for each split, focus the leaf to split and
move the new window in with force_split = 2 (always right/bottom). If dwindle
picks the wrong orientation for the box, togglesplit fixes it (preserve_split
keeps it). Split ratios are then restored by resizing
windows back to their original sizes.
"""
import json
import subprocess
import sys


def hypr(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def hypr_json(*args):
    return json.loads(hypr(*args, "-j"))


def dispatch(expr):
    hypr("dispatch", expr)


def clients():
    return {c["address"]: c for c in hypr_json("clients")}


def cut(wins):
    """Split wins by a full-length vertical ('h', side by side) or horizontal
    ('v', stacked) line. Returns (first, second, dir) or None."""
    for d, pos, size in (("h", 0, 0), ("v", 1, 1)):
        ws = sorted(wins, key=lambda c: c["at"][pos])
        for i in range(1, len(ws)):
            prev_end = max(c["at"][pos] + c["size"][size] for c in ws[:i])
            if prev_end <= ws[i]["at"][pos]:
                return ws[:i], ws[i:], d
    return None


def first_leaf(wins):
    parts = cut(wins)
    return first_leaf(parts[0]) if parts else wins[0]


def plan(wins):
    """Steps (window, window_to_split, dir) that rebuild wins' layout, assuming
    first_leaf(wins) is already placed in the region."""
    if len(wins) < 2:
        return []
    parts = cut(wins)
    if not parts:  # not a dwindle tree; fall back to reading order
        ws = sorted(wins, key=lambda c: (c["at"][1], c["at"][0]))
        return [(w, ws[i], None) for i, w in enumerate(ws[1:])]
    a, b, d = parts
    return [(first_leaf(b), first_leaf(a), d)] + plan(a) + plan(b)


def restore_sizes(orig):
    """Resizing one window moves its split, which also changes its
    neighbours, so a few passes are needed to settle."""
    for _ in range(4):
        now = clients()
        off = [c for c in orig if now[c["address"]]["size"] != c["size"]]
        if not off:
            return
        for c in off:
            w, h = c["size"]
            dispatch(f'hl.dsp.window.resize({{ x = {w}, y = {h}, window = "address:{c["address"]}" }})')


def main():
    target = int(sys.argv[1])
    source = int(sys.argv[2]) if len(sys.argv) > 2 else hypr_json("activeworkspace")["id"]
    if source == target:
        return

    wins = [c for c in clients().values() if c["workspace"].get("id") == source]
    if not wins:
        return
    tiled = [c for c in wins if not c["floating"]]
    floating = [c for c in wins if c["floating"]]
    focused = hypr_json("activewindow").get("address")

    def move(addr):
        dispatch(f'hl.dsp.window.move({{ workspace = {target}, window = "address:{addr}" }})')

    def focus(addr):
        dispatch(f'hl.dsp.focus({{ window = "address:{addr}" }})')

    old_split = hypr_json("getoption", "dwindle:force_split")["int"]
    hypr("eval", "hl.config({ dwindle = { force_split = 2 } })")
    try:
        if tiled:
            move(first_leaf(tiled)["address"])
            for win, split, d in plan(tiled):
                focus(split["address"])
                move(win["address"])
                if d:
                    now = clients()
                    w, s = now[win["address"]]["at"], now[split["address"]]["at"]
                    side_by_side = abs(w[0] - s[0]) > abs(w[1] - s[1])
                    if side_by_side != (d == "h"):
                        dispatch('hl.dsp.layout("togglesplit")')
            restore_sizes(tiled)
        for c in floating:
            move(c["address"])
        if focused:
            focus(focused)
    finally:
        hypr("eval", f"hl.config({{ dwindle = {{ force_split = {old_split} }} }})")


main()
