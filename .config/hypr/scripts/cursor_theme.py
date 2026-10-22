#!/usr/bin/env python3
"""Bibata cursor recolored with the rice accent.

Usage:
    cursor_theme.py build '#rrggbb'   rebuild Bibata-Rice in that color and switch to it
    cursor_theme.py off               back to the cursor from before Bibata-Rice
    cursor_theme.py on                re-enable (rebuilds with the accent currently on screen)
    cursor_theme.py status

theme-apply.py calls `build` in the background on every accent change, unless
it's switched off (theme/cursor.conf, which also picks the style: `original`
= sharp corners, `modern` = rounded). The theme is rendered from the vendored
SVGs in ~/.config/theme/bibata (upstream: ful1e5/Bibata_Cursor, GPL-3.0) into
~/.local/share/icons/Bibata-Rice, as both XCursor (every app, XWayland included)
and hyprcursor (SVG, what Hyprland itself draws, sharp at any scale).

Most Wayland apps (GTK4, Qt6, Firefox, Electron) ask Hyprland to draw the
cursor (cursor-shape-v1), so they follow `hyprctl setcursor` live. GTK3 and
XWayland apps load the theme themselves: GTK3 ones (Waybar!) only re-read it when
the gsettings theme *name* changes, see reload_gtk(); XWayland apps need a restart.

The hyprcursor half is built first (~0.3s) and shown right away; the XCursor
half (rasterizing every frame at every size, ~2s) follows for the apps.
"""
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import tomllib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

HOME = Path.home()
CONFIG = HOME / ".config"
SRC = CONFIG / "theme/bibata"
STATE_CONF = CONFIG / "theme/cursor.conf"          # enabled = true|false, style = original|modern
HYPR_CONF = CONFIG / "hypr/cursor.lua"             # read by hyprland.lua at startup
ICONS = HOME / ".local/share/icons"
BEFORE = HOME / ".local/state/theme/cursor-before.json"   # per machine, not in git
CACHE_DIR = HOME / ".cache/theme"
PIDFILE = CACHE_DIR / "cursor-build.pid"

NAME = "Bibata-Rice"
ALIAS = NAME + "-Reload"             # symlink to NAME, see reload_gtk()
SIZE = 28                            # keep in sync with XCURSOR_SIZE in hyprland.lua
# 1x/1.25x/1.5x/2x of the common sizes, so XCursor apps on scaled monitors get a crisp one.
XSIZES = [24, 28, 32, 36, 42, 48, 56, 64, 72, 84, 96]
CANVAS = 256                         # Bibata SVG viewBox; hotspots are given in it

OUTLINE = "#ffffff"                  # Bibata's placeholder colors -> ours
WATCH_BG = "#16181d"                 # disc behind the busy spinner (house "view" neutral)

GTK_INIS = [CONFIG / "gtk-3.0/settings.ini", CONFIG / "gtk-4.0/settings.ini"]
DEFAULT_INDEX = ICONS / "default/index.theme"      # XCursor fallback for apps that ignore settings


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


STYLES = ("original", "modern")      # subdirectories of SRC


def conf():
    out = {"enabled": "true", "style": "original"}
    try:
        for k, v in re.findall(r"^\s*(\w+)\s*=\s*(\S+)", STATE_CONF.read_text(), re.M):
            out[k] = v.lower()
    except OSError:
        pass
    if out["style"] not in STYLES:
        out["style"] = "original"
    return out


def enabled():
    return conf()["enabled"] != "false"


def set_enabled(on):
    write(STATE_CONF, "# Accent-colored Bibata cursor from theme-apply.py; toggle with\n"
                      "# ~/.config/hypr/scripts/cursor_theme.py on|off\n"
                      f"enabled = {'true' if on else 'false'}\n"
                      "# original = sharp corners, modern = rounded\n"
                      f"style = {conf()['style']}\n")


# -- building -----------------------------------------------------------------

def recolor(svg, accent):
    for placeholder, color in (("#00FF00", accent), ("#0000FF", OUTLINE), ("#FF0000", WATCH_BG)):
        svg = re.sub(placeholder, color, svg, flags=re.I)
    return svg


def render(svg_text, png):
    """One rsvg-convert per SVG at full size; the XCursor sizes are downscaled from it."""
    subprocess.run(["rsvg-convert", "-w", str(CANVAS), "-h", str(CANVAS), "-o", str(png)],
                   input=svg_text.encode(), check=True)


def xcursor(frames, hot, delay):
    """Encode an XCursor file: frames are CANVAS-sized RGBA images."""
    chunks = []
    for size in XSIZES:
        hx, hy = (min(size - 1, round(v * size / CANVAS)) for v in hot)
        for im in frames:
            r, g, b, a = im.resize((size, size), Image.LANCZOS).convert("RGBa").split()
            pixels = Image.merge("RGBA", (b, g, r, a)).tobytes()  # premultiplied ARGB, little-endian
            chunks.append((size, struct.pack("<9I", 36, 0xfffd0002, size, 1, size, size, hx, hy,
                                             delay if len(frames) > 1 else 0) + pixels))
    head = 16 + 12 * len(chunks)
    out = [struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(chunks))]
    pos = head
    for size, data in chunks:
        out.append(struct.pack("<III", 0xfffd0002, size, pos))
        pos += len(data)
    out += [data for _, data in chunks]
    return b"".join(out)


def shapes(style):
    """(name, svgs, hotspot, delay, symlinks) for every cursor in x.build.toml."""
    cfg = tomllib.loads((SRC / "x.build.toml").read_text())["cursors"]
    fallback = cfg.pop("fallback_settings")
    for key, c in cfg.items():
        pattern = c["png"].replace(".png", ".svg")
        if "*" in pattern:  # animated: <name>/<name>-NN.svg
            svgs = sorted((SRC / style / pattern.split("-*")[0]).glob(pattern))
        else:
            svgs = [SRC / style / pattern]
        yield (c.get("x11_name", key), svgs,
               (c.get("x_hotspot", fallback["x_hotspot"]), c.get("y_hotspot", fallback["y_hotspot"])),
               c.get("x11_delay", fallback["x11_delay"]), c.get("x11_symlinks", []))


def build_hyprcursor(accent, style, work):
    """Recolored SVGs + meta.hl per shape, compiled by hyprcursor-util. Returns the theme dir."""
    src = work / "src"
    for name, svgs, hot, delay, links in shapes(style):
        shape = src / "hyprcursors" / name
        shape.mkdir(parents=True)
        meta = [f"hotspot_x = {hot[0] / CANVAS:.3f}", f"hotspot_y = {hot[1] / CANVAS:.3f}",
                "resize_algorithm = bilinear"]
        meta += [f"define_override = {l}" for l in links]
        for svg in svgs:
            (shape / svg.name).write_text(recolor(svg.read_text(), accent))
            meta.append(f"define_size = 0, {svg.name}" + (f", {delay}" if len(svgs) > 1 else ""))
        (shape / "meta.hl").write_text("\n".join(meta) + "\n")
    (src / "manifest.hl").write_text(
        f"name = {NAME}\ndescription = Bibata {style} in the rice accent {accent}\n"
        "version = 1\ncursors_directory = hyprcursors\n")
    subprocess.run(["hyprcursor-util", "--create", str(src), "--output", str(work)],
                   check=True, capture_output=True)
    return next(work.glob("theme_*"))


def build_xcursor(accent, style, work, out):
    def one(shape):
        name, svgs, hot, delay, links = shape
        frames = []
        for svg in svgs:
            png = work / f"{svg.stem}.png"
            render(recolor(svg.read_text(), accent), png)
            frames.append(Image.open(png).convert("RGBA"))
        (out / name).write_bytes(xcursor(frames, hot, delay))
        for l in links:
            (out / l).symlink_to(name)

    out.mkdir(parents=True)
    with ThreadPoolExecutor(os.cpu_count() or 4) as pool:
        list(pool.map(one, shapes(style)))


def swap_in(new, final):
    """Replace final with new (file or dir) with only a rename-sized gap."""
    old = final.with_name(f".{final.name}.old.{os.getpid()}")
    if final.exists():
        final.rename(old)
    new.rename(final)
    if old.is_dir():
        shutil.rmtree(old, ignore_errors=True)
    else:
        old.unlink(missing_ok=True)


def take_over():
    """A newer accent change kills a build that's still running for an older one."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        old = int(PIDFILE.read_text())
        if old != os.getpid() and b"cursor_theme" in Path(f"/proc/{old}/cmdline").read_bytes():
            os.kill(old, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    PIDFILE.write_text(str(os.getpid()))


def install(accent, style, show):
    """Build both halves into ICONS/NAME; show() is called as soon as the
    hyprcursor half is in place. Returns False if that exact build already exists."""
    final = ICONS / NAME
    stamp = f"{style} {accent}"
    try:
        if (final / "stamp").read_text().strip() == stamp:
            return False
    except OSError:
        pass
    take_over()
    final.mkdir(parents=True, exist_ok=True)
    (final / "stamp").unlink(missing_ok=True)
    work = ICONS / f".{NAME}.work.{os.getpid()}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    try:
        hc = build_hyprcursor(accent, style, work)
        swap_in(hc / "hyprcursors", final / "hyprcursors")
        swap_in(hc / "manifest.hl", final / "manifest.hl")
        (final / "index.theme").write_text(
            f"[Icon Theme]\nName={NAME}\nComment=Bibata {style} in the rice accent {accent}\n")
        show()
        build_xcursor(accent, style, work, work / "cursors")
        swap_in(work / "cursors", final / "cursors")
        (final / "stamp").write_text(stamp + "\n")
        reload_gtk()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for stale in ICONS.glob(f".{NAME}.*"):  # leftovers of killed builds
        shutil.rmtree(stale, ignore_errors=True)
    return True


# -- switching the desktop ------------------------------------------------------

def ini_get(path, key):
    try:
        m = re.search(rf"^{re.escape(key)}\s*=\s*(.*)$", path.read_text(), re.M)
        return m.group(1).strip() if m else None
    except OSError:
        return None


def ini_set(path, key, value):
    """Set (or with value None, drop) a key in a GTK settings.ini [Settings] section."""
    try:
        text = path.read_text()
    except OSError:
        if value is None:
            return
        text = "[Settings]\n"
    pat = re.compile(rf"^{re.escape(key)}\s*=.*\n?", re.M)
    if value is None:
        text = pat.sub("", text)
    elif pat.search(text):
        text = pat.sub(f"{key}={value}\n", text)
    else:
        text = re.sub(r"^\[Settings\]\n", f"[Settings]\n{key}={value}\n", text, count=1, flags=re.M)
    write(path, text)


def snapshot():
    """What the cursor was before Bibata-Rice took over, so `off` can put it back."""
    gs = lambda k: run("gsettings", "get", "org.gnome.desktop.interface", k)
    kr = lambda k: run("kreadconfig6", "--file", "kcminputrc", "--group", "Mouse", "--key", k) or None
    return {
        "gsettings": {"cursor-theme": gs("cursor-theme"), "cursor-size": gs("cursor-size")},
        "gtk": {str(p): {k: ini_get(p, k) for k in ("gtk-cursor-theme-name", "gtk-cursor-theme-size")}
                for p in GTK_INIS},
        "kcminputrc": {"cursorTheme": kr("cursorTheme"), "cursorSize": kr("cursorSize")},
        "default_index": DEFAULT_INDEX.read_text() if DEFAULT_INDEX.exists() else None,
    }


def switch_to(snap):
    for k, v in snap["gsettings"].items():
        if v:
            run("gsettings", "set", "org.gnome.desktop.interface", k, v)
    for path, keys in snap["gtk"].items():
        for k, v in keys.items():
            ini_set(Path(path), k, v)
    for k, v in snap["kcminputrc"].items():
        args = ["--delete"] if v is None else [v]
        run("kwriteconfig6", "--file", "kcminputrc", "--group", "Mouse", "--key", k, *args)
    if snap["default_index"] is None:
        DEFAULT_INDEX.unlink(missing_ok=True)
    else:
        write(DEFAULT_INDEX, snap["default_index"])


def ours():
    return {
        "gsettings": {"cursor-theme": f"'{NAME}'", "cursor-size": str(SIZE)},
        "gtk": {str(p): {"gtk-cursor-theme-name": NAME, "gtk-cursor-theme-size": str(SIZE)}
                for p in GTK_INIS},
        "kcminputrc": {"cursorTheme": NAME, "cursorSize": str(SIZE)},
        "default_index": f"[Icon Theme]\nInherits={NAME}\n",
    }


def activate():
    if not BEFORE.exists():
        write(BEFORE, json.dumps(snapshot(), indent=2) + "\n")
    switch_to(ours())
    write(HYPR_CONF, f"-- Generated by cursor_theme.py - do not edit by hand.\nreturn {{ theme = \"{NAME}\" }}\n")
    set_hypr_cursor(NAME)


def reload_gtk():
    """GTK3 apps (Waybar's hover cursors) cache the XCursor theme until the
    gsettings cursor-theme name changes, so bounce it through an alias that
    points at the same files: they reload, and nothing visibly flickers."""
    alias = ICONS / ALIAS
    if not alias.is_symlink():
        alias.symlink_to(NAME)
    if run("gsettings", "get", "org.gnome.desktop.interface", "cursor-theme") != f"'{NAME}'":
        return  # turned off meanwhile
    run("gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", ALIAS)
    time.sleep(0.2)
    run("gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", NAME)


def set_hypr_cursor(theme):
    """`hyprctl setcursor` loads the new theme but keeps showing the old image
    until the pointer's shape next changes (e.g. a workspace switch). The one
    thing that forces a redraw with the current theme is un-hiding the cursor,
    and Hyprland only re-checks `cursor:invisible` on a 500ms ticker, so hide it
    across one tick and show it again (it blinks out for up to a second)."""
    run("hyprctl", "setcursor", theme, str(SIZE))
    run("hyprctl", "eval", "hl.config({ cursor = { invisible = true } })")
    time.sleep(0.55)
    run("hyprctl", "eval", "hl.config({ cursor = { invisible = false } })")


def deactivate():
    write(HYPR_CONF, "-- Generated by cursor_theme.py - do not edit by hand.\nreturn {}\n")
    try:
        snap = json.loads(BEFORE.read_text())
    except (OSError, ValueError):
        print("cursor_theme: no snapshot of the previous cursor, only Hyprland reset", file=sys.stderr)
    else:
        switch_to(snap)
        BEFORE.unlink()
    # Before Bibata-Rice Hyprland had no theme set, which resolves to XCursor "default".
    set_hypr_cursor("default")


def current_accent():
    try:
        return (CACHE_DIR / "current").read_text().strip()
    except OSError:
        return None


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "build":
        if len(args) < 2 or not re.fullmatch(r"#?[0-9a-fA-F]{6}", args[1]):
            sys.exit("usage: cursor_theme.py build '#rrggbb'")
        if not enabled():
            return
        accent = "#" + args[1].lstrip("#").lower()
        if not install(accent, conf()["style"], activate) and NAME not in (
                HYPR_CONF.read_text() if HYPR_CONF.exists() else ""):
            activate()
    elif cmd == "on":
        set_enabled(True)
        accent = current_accent() or "#33ccff"
        if not install(accent, conf()["style"], activate):
            activate()
        print(f"cursor: {NAME} ({conf()['style']}, {accent})")
    elif cmd == "off":
        set_enabled(False)
        deactivate()
        print("cursor: restored the previous cursor")
    elif cmd == "status":
        acc = (ICONS / NAME / "stamp").read_text().strip() if (ICONS / NAME / "stamp").exists() else "-"
        print(f"enabled={enabled()} built={acc} hyprland={HYPR_CONF.read_text().strip().splitlines()[-1] if HYPR_CONF.exists() else '-'}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
