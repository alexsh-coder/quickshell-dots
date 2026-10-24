#!/usr/bin/env python3
"""Minimal dot cursors in the accent color, as XCursor themes in ~/.local/share/icons.

Usage: cursor-dot.py '#rrggbb' [names...] [--as NAME]   builds (only the named ones of) Rice-Dot, Rice-Ring and Rice-Fluent
(--as: the one named, under another name; printed when done)

Fluent morphs between shapes: each one is a short animation starting from the dot,
whose last frame holds for an hour (Hyprland restarts it whenever the shape changes); the
plain dot itself is still.
"""
import os
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ICONS = Path.home() / ".local/share/icons"
SIZES = [24, 28, 32, 36, 40, 48, 56, 64, 72, 96]
SS = 4
FRAMES = 12

POINTER = ["default", "left_ptr", "arrow", "top_left_arrow", "right_ptr", "context-menu", "copy",
           "alias", "dnd-copy", "dnd-link", "dnd-move", "dnd-none", "dnd-no-drop", "no-drop",
           "not-allowed", "crossed_circle", "circle", "help", "question_arrow", "whats_this",
           "cell", "plus", "crosshair", "cross", "tcross", "vertical-text", "zoom-in", "zoom-out",
           "move", "fleur", "all-scroll", "size_all", "col-resize", "row-resize", "e-resize",
           "w-resize", "n-resize", "s-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize",
           "ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "size_hor", "size_ver",
           "size_bdiag", "size_fdiag", "sb_h_double_arrow", "sb_v_double_arrow", "h_double_arrow",
           "v_double_arrow", "left_side", "right_side", "top_side", "bottom_side",
           "top_left_corner", "top_right_corner", "bottom_left_corner", "bottom_right_corner",
           "split_h", "split_v", "grab", "openhand", "grabbing", "closedhand", "pencil", "X_cursor"]
HAND = ["pointer", "hand", "hand1", "hand2", "pointing_hand", "link"]
TEXT = ["text", "xterm", "ibeam"]
WAIT = ["wait", "watch", "progress", "left_ptr_watch", "half-busy"]


def rgb(hexstr):
    h = hexstr.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def canvas(size):
    s = size * SS
    return Image.new("RGBA", (s, s)), s


def done(im, size):
    return im.resize((size, size), Image.LANCZOS)


def circle(d, c, r, **kw):
    d.ellipse((c - r, c - r, c + r, c + r), **kw)


def dot(size, accent, style, big=False):
    im, s = canvas(size)
    d = ImageDraw.Draw(im)
    c = s / 2
    if style == "dot":
        r = s * (0.2 if big else 0.13)
        circle(d, c, r + s * 0.035, fill=(10, 12, 16, 150))
        circle(d, c, r, fill=accent + (255,))
    else:
        r = s * (0.3 if big else 0.22)
        w = max(SS, round(s * 0.05))
        circle(d, c, r + w * 0.6, outline=(10, 12, 16, 120), width=w * 2)
        circle(d, c, r, outline=accent + (255,), width=w)
        circle(d, c, s * 0.045, fill=accent + (255,))
    return done(im, size)


def bar(size, accent):
    im, s = canvas(size)
    d = ImageDraw.Draw(im)
    c, h, w = s / 2, s * 0.32, s * 0.035
    d.rounded_rectangle((c - w - SS * 2, c - h - SS * 2, c + w + SS * 2, c + h + SS * 2), w + SS * 2, fill=(10, 12, 16, 150))
    d.rounded_rectangle((c - w, c - h, c + w, c + h), w, fill=accent + (255,))
    return done(im, size)


def spinner(size, accent, frame):
    im, s = canvas(size)
    d = ImageDraw.Draw(im)
    c, r, w = s / 2, s * 0.24, max(SS, round(s * 0.06))
    box = (c - r, c - r, c + r, c + r)
    d.ellipse(box, outline=accent + (60,), width=w)
    a = frame * 360 / FRAMES
    d.arc(box, a, a + 110, fill=accent + (255,), width=w)
    circle(d, c, s * 0.05, fill=accent + (255,))
    return done(im, size)


def blob(size, accent, w, h, fill, edge):
    im, s = canvas(size)
    d = ImageDraw.Draw(im)
    c, w, h, p = s / 2, w * s / 2, h * s / 2, SS * 2
    d.rounded_rectangle((c - w - p, c - h - p, c + w + p, c + h + p), min(w, h) + p, fill=(10, 12, 16, 110))
    d.rounded_rectangle((c - w, c - h, c + w, c + h), min(w, h), fill=accent + (fill,),
                        outline=accent + (255,) if edge else None, width=max(SS, round(s * 0.03)))
    return done(im, size)


MORPH = 8
HOLD = 3600000
# (width, height, fill alpha, outlined) as fractions of the cursor size
SHAPES = {"dot": (0.2, 0.2, 255, False), "hand": (0.56, 0.56, 70, True), "text": (0.08, 0.6, 255, False)}


def morph(size, accent, frm, to, f):
    t = 1 - (1 - f / (MORPH - 1)) ** 3
    a, b = SHAPES[frm], SHAPES[to]
    lerp = lambda i: a[i] + (b[i] - a[i]) * t
    return blob(size, accent, lerp(0), lerp(1), round(lerp(2)), b[3] if t > 0.5 else a[3])


def xcursor(draw, nframes=1, delay=50, last=None):
    chunks = []
    for size in SIZES:
        for f in range(nframes):
            im = draw(size, f)
            r, g, b, a = im.convert("RGBa").split()
            px = Image.merge("RGBA", (b, g, r, a)).tobytes()
            chunks.append((size, struct.pack("<9I", 36, 0xfffd0002, size, 1, size, size, size // 2, size // 2,
                                             (last if last and f == nframes - 1 else delay) if nframes > 1 else 0) + px))
    out = [struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(chunks))]
    pos = 16 + 12 * len(chunks)
    for size, data in chunks:
        out.append(struct.pack("<III", 0xfffd0002, size, pos))
        pos += len(data)
    return b"".join(out + [d for _, d in chunks])


def build(name, style, accent):
    tmp = ICONS / f".{name}.new"
    shutil.rmtree(tmp, ignore_errors=True)
    cur = tmp / "cursors"
    cur.mkdir(parents=True)
    if style == "fluent":
        # The plain dot holds still: Hyprland restarts an animation whenever the shape is set
        # again (theme switches, windows re-setting it), and a shrink-in would jump each time
        groups = [(POINTER, xcursor(lambda s, f: morph(s, accent, "dot", "dot", 0))),
                  (HAND, xcursor(lambda s, f: morph(s, accent, "dot", "hand", f), MORPH, 16, HOLD)),
                  (TEXT, xcursor(lambda s, f: morph(s, accent, "dot", "text", f), MORPH, 16, HOLD))]
    else:
        groups = [(POINTER, xcursor(lambda s, f: dot(s, accent, style))),
                  (HAND, xcursor(lambda s, f: dot(s, accent, style, big=True))),
                  (TEXT, xcursor(lambda s, f: bar(s, accent)))]
    groups += [(WAIT, xcursor(lambda s, f: spinner(s, accent, f), FRAMES, 60))]
    for names, data in groups:
        (cur / names[0]).write_bytes(data)
        for n in names[1:]:
            (cur / n).symlink_to(names[0])
    (tmp / "index.theme").write_text(f"[Icon Theme]\nName={name}\nComment=Rice {style} cursor\n")
    final = ICONS / name
    old = ICONS / f".{name}.old"
    shutil.rmtree(old, ignore_errors=True)
    if final.exists():
        final.rename(old)
    tmp.rename(final)
    shutil.rmtree(old, ignore_errors=True)


if __name__ == "__main__":
    accent = rgb(sys.argv[1] if len(sys.argv) > 1 else "#33ccff")
    args = sys.argv[2:]
    alias = args[args.index("--as") + 1] if "--as" in args else None
    only = [a for a in args if a.startswith("Rice-")]
    for name, style in [("Rice-Dot", "dot"), ("Rice-Ring", "ring"), ("Rice-Fluent", "fluent")]:
        if not only or name in only:
            build(alias or name, style, accent)
            print(alias or name, flush=True)
