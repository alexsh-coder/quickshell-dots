#!/usr/bin/env python3
"""Preview strips of XCursor themes: arrow, hand and text cursor side by side, as PNGs.

Usage: cursor-preview.py OUT_DIR THEME_DIR...   writes OUT_DIR/<theme name>.png, printing each name
Strips newer than their theme are kept.
"""
import struct
import sys
from pathlib import Path

from PIL import Image

SHAPES = [("default", "left_ptr", "arrow"), ("pointer", "hand2", "hand1", "hand"), ("text", "xterm", "ibeam")]
CELL = 56
WANT = 48


def image(path):
    """The last frame (where an animation settles) at the nominal size closest to WANT, as RGBA."""
    data = path.read_bytes()
    magic, header, _, count = struct.unpack_from("<4sIII", data)
    if magic != b"Xcur":
        return None
    tocs = [struct.unpack_from("<III", data, header + 12 * i) for i in range(count)]
    imgs = [(sub, pos) for kind, sub, pos in tocs if kind == 0xfffd0002]
    if not imgs:
        return None
    best = min({s for s, _ in imgs}, key=lambda s: (abs(s - WANT), -s))
    pos = [p for s, p in imgs if s == best][-1]
    w, h = struct.unpack_from("<II", data, pos + 16)
    px = data[pos + 36:pos + 36 + w * h * 4]
    b, g, r, a = Image.frombytes("RGBA", (w, h), px).split()
    return Image.merge("RGBa", (r, g, b, a)).convert("RGBA")


def strip(theme):
    out = Image.new("RGBA", (CELL * len(SHAPES), CELL))
    for i, names in enumerate(SHAPES):
        f = next((theme / "cursors" / n for n in names if (theme / "cursors" / n).exists()), None)
        try:
            im = image(f.resolve()) if f else None
        except (OSError, struct.error, ValueError):
            im = None
        if not im:
            continue
        im = im.crop(im.getbbox() or (0, 0, 1, 1))
        k = min(1, (CELL - 6) / max(im.size))
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        out.alpha_composite(im, (i * CELL + (CELL - im.width) // 2, (CELL - im.height) // 2))
    return out


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for t in map(Path, sys.argv[2:]):
        png = out / f"{t.name}.png"
        try:
            if not png.exists() or png.stat().st_mtime < (t / "cursors").stat().st_mtime:
                strip(t).save(png)
        except OSError:
            continue
        print(t.name, flush=True)


if __name__ == "__main__":
    main()
