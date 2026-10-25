#!/usr/bin/env python3
"""Copies an XCursor theme recolored, as Tinted-<rrggbb>-<name> in ~/.local/share/icons.

Prints the copy's name, followed by its sizes when it has only some (see ONLY_SIZE), and
"-name" for each old copy it deletes.

Usage: cursor-recolor.py THEME_DIR '#rrggbb' [contrast]
       cursor-recolor.py THEME_DIR none     same colors, as Fixed-<name>

With ONLY_SIZE=n in the environment just that size is built, fast, and the copy is marked partial
(not counted as cached) until a full build replaces it.

Either way every size in SIZES is added, and missing names are linked to ones the theme has.

With contrast the outline is redrawn black or white against the new color (for plain black or
white cursors); without it the theme's own outline stays, unless it would blend into the new body.

Colorful themes get their hue swapped for the accent's; black-and-white ones get the body
(the larger of the dark and light parts) painted in it, keeping the outline.
"""
import os
import shutil
import struct
from concurrent.futures import ProcessPoolExecutor
import sys
from pathlib import Path


ICONS = Path.home() / ".local/share/icons"
SIZES = [20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 96]
# Each wanted size (the setting, times every monitor scale) as the SIZES steps around it
ONLY = sorted({f(s for s in SIZES if c(s, int(v))) for v in os.environ.get("ONLY_SIZE", "").split(",") if v
               for f, c in ((min, lambda s, v: s >= v or s == SIZES[-1]), (max, lambda s, v: s <= v or s == SIZES[0]))})
# Recolored copies kept around, so switching back is instant (Fixed- ones all stay)
KEEP = 120


def cached(name):
    """Prints and returns True when that build is already there."""
    d = ICONS / name
    part = d / "partial"
    if d.is_dir() and (not part.exists() or ONLY and set(ONLY) <= set(map(int, part.read_text().split() or [0]))):
        os.utime(d)
        print(name, part.read_text() if part.exists() else "")
        return True
    return False


def target(argv):
    src = Path(argv[1])
    if argv[2] == "none":
        return "Fixed-" + src.name
    return f"Tinted-{argv[2].lstrip('#').lower()}-{src.name}"


if __name__ == "__main__" and cached(target(sys.argv)):
    sys.exit(0)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

# Nominal sizes every built theme gets, so each size setting looks different

IMAGE = 0xfffd0002
# Names that mean the same shape: CSS ones (what cursor-shape-v1 clients ask for) and X11 ones.
# Some themes (Oxygen, KDE Classic) lack "default", and Hyprland then falls back to some other theme
SAME = [
    ["default", "left_ptr", "arrow", "top_left_arrow"],
    ["pointer", "hand2", "hand1", "pointing_hand", "hand"],
    ["text", "xterm", "ibeam"],
    ["wait", "watch"],
    ["progress", "left_ptr_watch", "half-busy"],
    ["crosshair", "cross", "tcross"],
    ["move", "fleur", "size_all", "all-scroll"],
    ["grab", "openhand"],
    ["grabbing", "closedhand"],
    ["not-allowed", "crossed_circle", "forbidden", "no-drop"],
    ["help", "question_arrow", "whats_this"],
    ["e-resize", "right_side"],
    ["w-resize", "left_side"],
    ["n-resize", "top_side"],
    ["s-resize", "bottom_side"],
    ["ne-resize", "top_right_corner"],
    ["nw-resize", "top_left_corner"],
    ["se-resize", "bottom_right_corner"],
    ["sw-resize", "bottom_left_corner"],
    ["ew-resize", "sb_h_double_arrow", "h_double_arrow", "size_hor", "col-resize", "split_h"],
    ["ns-resize", "sb_v_double_arrow", "v_double_arrow", "size_ver", "row-resize", "split_v"],
    ["nesw-resize", "fd_double_arrow", "size_bdiag"],
    ["nwse-resize", "bd_double_arrow", "size_fdiag"],
    ["context-menu", "default"],
    ["copy", "dnd-copy", "default"],
    ["alias", "dnd-link", "default"],
]


def read(path):
    data = path.read_bytes()
    magic, hsize, _, n = struct.unpack_from("<4sIII", data)
    if magic != b"Xcur":
        return None
    toc = [struct.unpack_from("<III", data, hsize + 12 * i) for i in range(n)]
    out = []
    for typ, sub, pos in toc:
        if typ != IMAGE:
            continue
        head = struct.unpack_from("<9I", data, pos)
        w, h = head[4], head[5]
        px = np.frombuffer(data, np.uint8, w * h * 4, pos + head[0]).reshape(h, w, 4)
        out.append((head, px))
    return out


def write(path, images):
    chunks = [struct.pack("<9I", *head) + px.tobytes() for head, px in images]
    out = [struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(chunks))]
    pos = 16 + 12 * len(chunks)
    for (head, _), c in zip(images, chunks):
        out.append(struct.pack("<III", IMAGE, head[2], pos))
        pos += len(c)
    path.write_bytes(b"".join(out + chunks))


def straight(px):
    """BGRA premultiplied -> float RGB straight, alpha."""
    f = px.astype(np.float32) / 255
    a = f[..., 3:4]
    rgb = np.where(a > 0, f[..., 2::-1] / np.maximum(a, 1e-6), 0)
    return np.clip(rgb, 0, 1), a


def premul(rgb, a):
    out = np.concatenate([rgb[..., ::-1] * a, a], axis=-1)
    return np.round(np.clip(out, 0, 1) * 255).astype(np.uint8)


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    return mx, np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)


def mode(all_images):
    """'hue' for colorful themes, else 'dark' or 'light' for which part is the body."""
    sat = dark = light = total = 0
    for _, px in all_images:
        rgb, a = straight(px)
        on = a[..., 0] > 0.8
        v, s = hsv(rgb)
        total += on.sum()
        sat += (on & (s > 0.35) & (v > 0.25)).sum()
        dark += (on & (v < 0.4)).sum()
        light += (on & (v > 0.6)).sum()
    if total and sat / total > 0.15:
        return "hue"
    return "dark" if dark >= light else "light"


def luminance(rgb):
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def blends(accent, how):
    """True when a black-and-white theme's outline (white around a dark body, black around a
    light one) has under 3:1 contrast with the accent."""
    y, edge = luminance(accent), 1.0 if how == "dark" else 0.0
    return (max(y, edge) + 0.05) / (min(y, edge) + 0.05) < 3


def recolor(px, how, accent, contrast):
    rgb, a = straight(px)
    acc = np.array(accent, np.float32)
    v, s = hsv(rgb)
    if how == "hue":
        # Rebuild each colorful pixel from the new color, keeping some of its shading
        shade = np.clip(acc * (0.6 + 0.45 * v[..., None]), 0, 1)
        t = np.clip((s - 0.15) / 0.25, 0, 1)[..., None]
        new = rgb * (1 - t) + shade * t
    else:
        # Body pixels become the accent, shaded by how far they sit from the body's tone
        t = np.clip((0.55 - v) / 0.3, 0, 1) if how == "dark" else np.clip((v - 0.45) / 0.3, 0, 1)
        # Soft shadows stay as they are
        t = t * np.clip(1 - s / 0.5, 0, 1) * np.clip((a[..., 0] - 0.55) / 0.3, 0, 1)
        t = t[..., None]
        shade = 0.85 + 0.15 * (v[..., None] if how == "light" else 1 - v[..., None])
        new = rgb * (1 - t) + acc * shade * t
    if contrast:
        edge = np.array([0.07] * 3 if acc.mean() > 0.5 else [0.97] * 3, np.float32)
        o = (1 - t) * np.clip((a - 0.55) / 0.3, 0, 1)
        new = new * (1 - o) + edge * o
    return premul(new, a)


def plan(heads):
    """{nominal: (source nominal, new image size or None to scale by the nominal)} for one file.

    Tiny pixel-art cursors (KDE Classic draws a 10 px arrow at nominal 24) are redone at every
    size, grown by whole steps so the pixels stay crisp."""
    have = {}
    for h in heads:
        have.setdefault(h[2], h[4])
    ratio = min(w / n for n, w in have.items())
    out = {}
    for t in SIZES:
        src = min((n for n in have if n >= t), default=max(have))
        if ratio < 0.6:
            w = have[src]
            out[t] = (src, w * max(1, round(0.7 * t / w)))
        elif t not in have:
            out[t] = (src, None)
    return out


def scale(head, px, nominal, size):
    """One image resampled for another nominal size."""
    w, h = head[4], head[5]
    f = size / w if size else nominal / head[2]
    nw, nh = max(1, round(w * f)), max(1, round(h * f))
    im = Image.frombytes("RGBa", (w, h), px.tobytes())
    im = im.resize((nw, nh), Image.NEAREST if size and f == int(f) else Image.LANCZOS)
    hx, hy = min(nw - 1, round(head[6] * f)), min(nh - 1, round(head[7] * f))
    new = (head[0], head[1], nominal, head[3], nw, nh, hx, hy, head[8])
    return new, np.frombuffer(im.tobytes(), np.uint8).reshape(nh, nw, 4)


def one(job):
    """Images lo..hi of one file, recolored (unless how is None), plus the sizes added from them."""
    src, lo, hi, how, accent, contrast, sizes = job
    imgs = read(src)[lo:hi]
    if ONLY:
        if how:
            imgs = [(head, recolor(px, how, accent, contrast)) for head, px in imgs if head[2] in {n for n, _ in sizes.values()}]
        keep, added = [], []
        for t, (n, size) in sizes.items():
            src_imgs = [im for im in imgs if im[0][2] == n]
            if n == t and not size:
                keep += src_imgs
            else:
                added += [scale(head, px, t, size) for head, px in src_imgs]
        return keep, added
    if how:
        imgs = [(head, recolor(px, how, accent, contrast)) for head, px in imgs]
    redone = {t for t, (_, size) in sizes.items() if size}
    keep = [im for im in imgs if im[0][2] not in redone]
    added = [scale(head, px, t, size) for t, (n, size) in sorted(sizes.items()) for head, px in imgs if head[2] == n]
    return keep, added


def fill(cursors):
    """Links every missing name of a shape to one the theme has."""
    for group in SAME:
        have = next((n for n in group if (cursors / n).exists()), None)
        if have:
            for n in group:
                if not (cursors / n).exists() and not (cursors / n).is_symlink():
                    (cursors / n).symlink_to(have)


def swap(tmp, name):
    final, old = ICONS / name, ICONS / f".{name}.old"
    shutil.rmtree(old, ignore_errors=True)
    if final.exists():
        final.rename(old)
    tmp.rename(final)
    shutil.rmtree(old, ignore_errors=True)
    # Printed as "name" when complete, "name 48 56 ..." with just those sizes
    print(name, " ".join(map(str, ONLY)))
    # Never the one on screen; "-name" tells the caller it's gone
    try:
        shown = (ICONS / "default/index.theme").read_text().split("Inherits=")[1].split()[0]
    except (OSError, IndexError):
        shown = ""
    for d in sorted(ICONS.glob("Tinted-*"), key=lambda d: d.stat().st_mtime, reverse=True)[KEEP:]:
        if d.name not in (shown, name):
            shutil.rmtree(d, ignore_errors=True)
            print("-" + d.name)


def main():
    src = Path(sys.argv[1])
    plain = sys.argv[2] == "none"
    h = "000000" if plain else sys.argv[2].lstrip("#")
    accent = tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    contrast = len(sys.argv) > 3 and sys.argv[3] == "contrast"
    name = target(sys.argv)
    tmp = ICONS / f".{name}.new"
    shutil.rmtree(tmp, ignore_errors=True)
    (tmp / "cursors").mkdir(parents=True)

    files = [f.name for f in sorted((src / "cursors").iterdir()) if not f.is_symlink()]
    sample = []
    for k in ("left_ptr", "default", "pointer", "hand2", "xterm", *files[:1]):
        try:
            sample += read((src / "cursors" / k).resolve()) or []
        except (OSError, struct.error, ValueError):
            pass
    how = None if plain else mode(sample)
    contrast = contrast or how in ("dark", "light") and blends(accent, how)

    # Work in slices of a file's images, so the big animated ones don't hold everything up
    step = 16
    jobs, parts = [], {}
    for n in files:
        try:
            heads = [h for h, _ in read(src / "cursors" / n) or []]
        except (OSError, struct.error, ValueError):
            heads = []
        count = len(heads)
        if not count:
            shutil.copyfile(src / "cursors" / n, tmp / "cursors" / n)
            continue
        parts[n] = range(0, count, step)
        sizes = plan(heads)
        if ONLY:
            have = sorted({h[2] for h in heads})
            sizes = {t: sizes.get(t, (min((x for x in have if x >= t), default=have[-1]), None)) for t in ONLY}
        jobs += [(src / "cursors" / n, lo, lo + step, how, accent, contrast, sizes) for lo in parts[n]]
    with ProcessPoolExecutor(os.cpu_count() or 4) as pool:
        done = map(one, jobs) if ONLY else pool.map(one, jobs)
        for n, chunks in parts.items():
            results = [next(done) for _ in chunks]
            # Frames stay in order within each size
            write(tmp / "cursors" / n, [im for keep, _ in results for im in keep] + sorted(
                (im for _, added in results for im in added), key=lambda im: im[0][2]))

    for f in (src / "cursors").iterdir():
        if f.is_symlink():
            (tmp / "cursors" / f.name).symlink_to(os.readlink(f))
    fill(tmp / "cursors")
    (tmp / "index.theme").write_text(f"[Icon Theme]\nName={name}\nInherits=Adwaita\n")
    if ONLY:
        (tmp / "partial").write_text(" ".join(map(str, ONLY)))
    swap(tmp, name)


if __name__ == "__main__":
    main()
