#!/usr/bin/env python3
"""Derive an accent color from a wallpaper and push it to the whole desktop.

Usage:
    theme-apply.py [WALLPAPER]      apply accent for WALLPAPER (default: current awww image)
    theme-apply.py --no-anim [...]  same, but switch instantly
    theme-apply.py --pin '#ff8a5c'  hardcode an accent for the current wallpaper
    theme-apply.py --unpin          drop the hardcoded accent, go back to auto
    theme-apply.py --preview        print the accent for every wallpaper, apply nothing

Accent priority: ~/.config/theme/accents.conf override -> matugen (cached) -> DEFAULT.

Transitions: Waybar animates natively (a GTK CSS `transition` is switched on
in colors.css only for the duration of the change, so normal hover/workspace
changes stay instant), fed a few OKLCH waypoints so it doesn't fade via gray. The Hyprland border has no such thing, so it's stepped
here in OKLCH at ~60fps via `hyprctl eval` (~6ms per call).

GTK/Qt apps switch instantly: see apply_kde_scheme(). The cursor is rebuilt in the
accent by cursor_theme.py.
"""
import configparser
import json
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / ".config"
WALLPAPERS = HOME / "Pictures/wallpapers"
OVERRIDES = CONFIG / "theme/accents.conf"
CACHE_DIR = HOME / ".cache/theme"
CACHE = CACHE_DIR / "auto-accents.json"
CURRENT = CACHE_DIR / "current"    # accent currently on screen (updated per frame)
PIDFILE = CACHE_DIR / "theme-apply.pid"

DEFAULT = "#33ccff"
DURATION = 1.0                      # seconds, shared by Waybar and the border
FPS = 60
WAYBAR_SEGMENTS = 6                 # CSS reloads per transition (see apply())

# Auto accents are normalized to the house look (#33ccff is L 0.79 C 0.14):
# same lightness for every wallpaper, chroma pushed into a vivid-but-not-neon band.
TARGET_L = 0.79
MIN_C, MAX_C = 0.12, 0.17
GRAY_C = 0.035                      # source colors below this chroma don't count as a hue


# -- color math (sRGB <-> OKLab/OKLCH) -----------------------------------------

def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return "#" + "".join(f"{round(min(1, max(0, c)) * 255):02x}" for c in rgb)


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb_to_oklch(rgb):
    r, g, b = (_lin(c) for c in rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def oklch_to_rgb_raw(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return r, g, bl


def oklch_to_rgb(L, C, H):
    """Gamut-map by reducing chroma until the color fits in sRGB."""
    lo, hi = 0.0, C
    rgb = oklch_to_rgb_raw(L, C, H)
    if all(-1e-4 <= c <= 1 + 1e-4 for c in rgb):
        return tuple(_gam(max(0, c)) for c in rgb)
    for _ in range(24):
        mid = (lo + hi) / 2
        if all(-1e-4 <= c <= 1 + 1e-4 for c in oklch_to_rgb_raw(L, mid, H)):
            lo = mid
        else:
            hi = mid
    return tuple(_gam(min(1, max(0, c))) for c in oklch_to_rgb_raw(L, lo, H))


def mix_oklch(h1, h2, t):
    L1, C1, H1 = rgb_to_oklch(hex_to_rgb(h1))
    L2, C2, H2 = rgb_to_oklch(hex_to_rgb(h2))
    dh = (H2 - H1 + 180) % 360 - 180         # shortest way around the hue wheel
    return rgb_to_hex(oklch_to_rgb(L1 + (L2 - L1) * t, C1 + (C2 - C1) * t, H1 + dh * t))


def ease_in_out(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)  # matches CSS ease-in-out closely enough


# -- choosing the accent --------------------------------------------------------

def is_hex(s):
    s = s.strip().lstrip("#")
    return len(s) == 6 and all(c in "0123456789abcdefABCDEF" for c in s)


def read_overrides():
    out = {}
    if OVERRIDES.exists():
        for line in OVERRIDES.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, color = (x.strip() for x in line.rsplit("=", 1))
            if is_hex(color):
                out[name] = "#" + color.lstrip("#").lower()
    return out


def auto_accent(path):
    """matugen's source colors come ordered by dominance; take the first real hue."""
    st = path.stat()
    key = f"{path}|{st.st_mtime_ns}|{st.st_size}"
    try:
        cache = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        cache = {}
    if key in cache:
        return cache[key]

    out = subprocess.run(["matugen", "image", str(path), "--show-source-colors"],
                         capture_output=True, text=True, timeout=10).stdout
    accent = None
    for tok in out.split():
        if not is_hex(tok):
            continue
        L, C, H = rgb_to_oklch(hex_to_rgb(tok))
        if C >= GRAY_C:
            accent = rgb_to_hex(oklch_to_rgb(TARGET_L, min(max(C, MIN_C), MAX_C), H))
            break
    accent = accent or DEFAULT

    cache = {k: v for k, v in cache.items() if Path(k.split("|")[0]).exists()}
    cache[key] = accent
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, indent=1))
    return accent


def accent_for(path):
    overrides = read_overrides()
    if path.name in overrides:
        return overrides[path.name], "pinned"
    try:
        return auto_accent(path), "auto"
    except Exception as e:  # matugen missing/broken image: never leave the desktop half-themed
        print(f"theme-apply: auto accent failed ({e}), using default", file=sys.stderr)
        return DEFAULT, "default"


def current_wallpaper():
    try:
        out = subprocess.run(["awww", "query"], capture_output=True, text=True, timeout=2).stdout
        for line in out.splitlines():
            if "image: " in line:
                return Path(line.split("image: ", 1)[1].strip())
    except Exception:
        pass
    return None


# -- writers ---------------------------------------------------------------------

def write(path, text):
    """Atomic replace, so file watchers never see a half-written file."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


HEADER = "Generated by ~/.config/hypr/scripts/theme-apply.py - do not edit by hand."


def waybar_css(accent, transition_ms=0):
    css = f"/* {HEADER} */\n@define-color accent {accent};\n"
    if transition_ms:
        t = f"{transition_ms}ms linear"
        css += f"* {{ transition: color {t}, background-color {t}, text-shadow {t}; }}\n"
    return css


WLOGOUT_ICONS = Path("/usr/share/wlogout/icons")
WLOGOUT_ICON_DIR = CACHE_DIR / "wlogout-icons"


def wlogout_icon_css(accent):
    """The stock wlogout icons are PNGs with the color baked in, and GTK CSS
    can't tint images -- so recolor them here: keep each icon's alpha, fill
    with the accent. `window #id` outranks the plain `#id` rules in style.css,
    which stay as the fallback if Pillow is missing."""
    try:
        from PIL import Image
    except ImportError:
        return ""
    WLOGOUT_ICON_DIR.mkdir(parents=True, exist_ok=True)
    a = accent.lstrip("#")
    rgb = tuple(round(c * 255) for c in hex_to_rgb(accent))
    css = ""
    for src in sorted(WLOGOUT_ICONS.glob("*.png")):
        # accent in the file name: GTK caches images by URL, and it doubles as a cache
        dst = WLOGOUT_ICON_DIR / f"{src.stem}-{a}.png"
        if not dst.exists():
            alpha = Image.open(src).convert("RGBA").getchannel("A")
            icon = Image.new("RGBA", alpha.size, rgb + (255,))
            icon.putalpha(alpha)
            icon.save(dst)
        css += f'window #{src.stem} {{ background-image: image(url("{dst}")); }}\n'
    for old in WLOGOUT_ICON_DIR.glob("*.png"):
        if not old.stem.endswith(a):
            old.unlink()
    return css


SDDM_CONF = Path("/var/lib/wallpaper-sync/theme.conf.user")  # sugar-candy's theme.conf.user symlinks here


def sddm_accent(accent):
    if not SDDM_CONF.exists():
        return
    lines = [l for l in SDDM_CONF.read_text().splitlines() if not l.startswith("AccentColor=")]
    i = lines.index("[General]") + 1 if "[General]" in lines else 0
    lines.insert(i, f'AccentColor="{accent}"')
    write(SDDM_CONF, "\n".join(lines) + "\n")


# ANSI hues pulled 30% toward the accent and toned down, so the terminal
# palette (and fastfetch's color dots) reads as one family with the wallpaper.
# Green (2/10) is the accent itself: cmatrix, tty-clock, unimatrix etc. draw
# in ANSI green by default, so this makes them follow the accent.
ANSI_HUES = {1: 25, 3: 90, 5: 330, 6: 200}
KITTY_BLACK = "#1e2026"  # color0 in kitty.conf; cmatrix paints its background with it


def ansi_palette(accent):
    _, _, ha = rgb_to_oklch(hex_to_rgb(accent))
    pal = {2: accent, 4: accent, 10: accent, 12: accent}
    for n, h in ANSI_HUES.items():
        h = h + ((ha - h + 180) % 360 - 180) * 0.3
        pal[n] = rgb_to_hex(oklch_to_rgb(0.70, 0.10, h))
        pal[n + 8] = rgb_to_hex(oklch_to_rgb(0.80, 0.09, h))
    return dict(sorted(pal.items()))


def fastfetch_config(accent):
    """Boxed layout with Nerd Font icons, keys fade accent -> its hue neighbour."""
    L, C, H = rgb_to_oklch(hex_to_rgb(accent))
    end = rgb_to_hex(oklch_to_rgb(0.72, C, H + 45))
    frame = "#6b7078"
    line = "─" * 50
    top = {"type": "custom", "format": f"┌{line}┐", "outputColor": frame}
    bot = {"type": "custom", "format": f"└{line}┘", "outputColor": frame}
    groups = [
        [("os", "\U000f08c7", "OS"), ("kernel", "", "Kernel"),
         ("packages", "\U000f03d7", "Packages"), ("display", "\U000f0379", "Display"),
         ("terminal", "", "Terminal"), ("wm", "\U000f05ad", "WM")],
        [("cpu", "\U000f0ee0", "CPU"), ("gpu", "\U000f08ae", "GPU"),
         ("memory", "\U000f035b", "Memory"), ("uptime", "\U000f0150", "Uptime")],
    ]
    n = sum(len(g) for g in groups)
    modules, i = [], 0
    for g in groups:
        modules.append(top)
        for typ, icon, label in g:
            modules.append({"type": typ, "key": f"  {icon} {label:<9}",
                            "keyColor": mix_oklch(accent, end, i / (n - 1)),
                            **({"format": "{width}x{height} @ {refresh-rate} Hz"} if typ == "display" else {})})
            i += 1
        modules.append(bot)
    modules += [{"type": "custom", "format": "┌" + "─" * 18 + "┐", "outputColor": frame},
                {"type": "custom", "format": "  " + " ".join(f"{{#{c}}}\u25cf" for c in (90, 37, 31, 32, 33, 34, 35, 36))},
                {"type": "custom", "format": "└" + "─" * 18 + "┘", "outputColor": frame}]
    cfg = {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": {"type": "file-raw", "source": "~/.config/fastfetch/logo.txt",
                 "padding": {"right": 4}},
        "display": {"separator": ": "},
        "modules": modules,
    }
    return f"// {HEADER}\n" + json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"


def fastfetch_logo(accent):
    """arch-braille.txt as drawn, with the same accent -> neighbour fade as the keys."""
    _, C, H = rgb_to_oklch(hex_to_rgb(accent))
    end = rgb_to_hex(oklch_to_rgb(0.72, C, H + 45))
    rows = (CONFIG / "fastfetch/arch-braille.txt").read_text().rstrip("\n").split("\n")
    out = []
    for y, row in enumerate(rows):
        r, g, b = (int(c * 255 + 0.5) for c in hex_to_rgb(mix_oklch(accent, end, y / max(len(rows) - 1, 1))))
        out.append(f"\x1b[38;2;{r};{g};{b}m{row}\x1b[0m")
    return "\n".join(out) + "\n"


def cava_theme(accent):
    """Cava bars: 8-step OKLCH gradient bottom->top ending at the accent. The bottom
    is the same hue, darker and more saturated, so the bars read as the accent
    (a hue shift made e.g. a lavender accent end in red)."""
    L, C, H = rgb_to_oklch(hex_to_rgb(accent))
    base = rgb_to_hex(oklch_to_rgb(L - 0.22, min(C + 0.05, 0.22), H))
    stops = [accent if i == 7 else mix_oklch(base, accent, i / 7) for i in range(8)]
    return (f"# {HEADER}\n[color]\ngradient = 1\n"
            + "".join(f"gradient_color_{i + 1} = '{c}'\n" for i, c in enumerate(stops)))


def reload_cava():
    """SIGUSR2 makes cava re-read its colors (theme file included). Only real cava
    binaries are signalled: ~/.local/bin/cava is a bash wrapper (same process name)
    that restarts cava if the reload crashes it, and bash would die from SIGUSR2."""
    pids = subprocess.run(["pgrep", "-x", "cava"], capture_output=True, text=True).stdout.split()
    for pid in pids:
        try:
            if os.readlink(f"/proc/{pid}/exe") == "/usr/bin/cava":
                os.kill(int(pid), signal.SIGUSR2)
        except OSError:
            pass


def write_static(accent):
    """Everything that doesn't animate: just rewrite and reload."""
    a = accent.lstrip("#")
    write(CONFIG / "wofi/colors.css", f"/* {HEADER} */\n@define-color accent {accent};\n")
    write(CONFIG / "wlogout/colors.css",
          f"/* {HEADER} */\n@define-color accent {accent};\n" + wlogout_icon_css(accent))
    write(CONFIG / "hypr/colors.lua", f"-- {HEADER}\nreturn {{ accent = \"{a}\" }}\n")

    dunst_d = CONFIG / "dunst/dunstrc.d"
    dunst_d.mkdir(exist_ok=True)
    write(dunst_d / "90-theme.conf",
          f"# {HEADER}\n[global]\n    frame_color = \"{accent}\"\n"
          f"[urgency_normal]\n    frame_color = \"{accent}\"\n")
    # If dunst isn't running, D-Bus activation may pick plasma_waitforname for
    # org.freedesktop.Notifications and hang ~25s -- never let that delay the accent.
    try:
        subprocess.run(["dunstctl", "reload"], capture_output=True, timeout=1)
    except subprocess.TimeoutExpired:
        pass

    # osd.py watches this file and reloads its CSS itself.
    write(CONFIG / "osd/colors.css", f"/* {HEADER} */\n@define-color accent {accent};\n")

    apply_kde_scheme(accent)
    sddm_accent(accent)
    zen_theme(accent)

    kitty_colors = CONFIG / "kitty/theme-colors.conf"
    write(kitty_colors, f"# {HEADER}\ncursor {accent}\nselection_background {accent}\n"
                        + "".join(f"color{n} {c}\n" for n, c in ansi_palette(accent).items()))
    write(CONFIG / "fastfetch/logo.txt", fastfetch_logo(accent))
    write(CONFIG / "fastfetch/config.jsonc", fastfetch_config(accent))
    write(CONFIG / "cava/themes/rice", cava_theme(accent))
    reload_cava()
    # Bibata recolor takes ~2.5s, so it runs on its own (no-op when turned off, see cursor_theme.py).
    subprocess.Popen([str(Path(__file__).with_name("cursor_theme.py")), "build", accent],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    pids = subprocess.run(["pgrep", "-x", "kitty"], capture_output=True, text=True).stdout.split()
    for pid in pids:  # kitty suffixes the abstract socket name with -<pid>
        sock = f"unix:@kitty-{pid}"
        subprocess.run(["kitty", "@", "--to", sock, "set-colors", "--all",
                        "--configured", str(kitty_colors)], capture_output=True, timeout=2)
        keep_cmatrix_transparent(sock)


def keep_cmatrix_transparent(sock):
    """set-colors --configured clears the see-through black that the cmatrix()
    wrapper in ~/.bashrc turns on, so put it back in windows running cmatrix."""
    try:
        out = subprocess.run(["kitty", "@", "--to", sock, "ls"], capture_output=True,
                             text=True, timeout=2).stdout
        wins = [w for o in json.loads(out) for t in o["tabs"] for w in t["windows"]]
    except (subprocess.SubprocessError, ValueError, KeyError):
        return
    for w in wins:
        if any(Path(p["cmdline"][0]).name == "cmatrix"
               for p in w.get("foreground_processes", []) if p.get("cmdline")):
            subprocess.run(["kitty", "@", "--to", sock, "set-colors", "--match", f"id:{w['id']}",
                            f"transparent_background_colors={KITTY_BLACK}"],
                           capture_output=True, timeout=2)


# -- GTK/Qt apps -------------------------------------------------------------------
# One KDE color scheme drives both toolkits: Qt apps read it from kdeglobals
# (QT_QPA_PLATFORMTHEME=kde), and kded6's gtkconfig module translates it into
# ~/.config/gtk-{3,4}.0/colors.css, which the Breeze GTK theme is built on.
# plasma-apply-colorscheme won't re-apply the scheme that's already current,
# so it alternates between two file names.

SCHEMES = HOME / ".local/share/color-schemes"

# House neutrals, same family as the Waybar pill (rgba(30,32,38)).
NEUTRAL = {
    "view": "#16181d",      # lists, text fields, document areas
    "window": "#1e2026",
    "raised": "#272a31",    # buttons, headers' alternate
    "header": "#1a1c21",
    "fg": "#e0e0e0",
    "muted": "#8a8f9a",
    "negative": "#ff6b6b",
    "neutral": "#ffcc66",
    "positive": "#8fd694",
    "visited": "#b48ead",
}


def _rgb(h):
    return ",".join(str(round(c * 255)) for c in hex_to_rgb(h))


def _blend(fg, bg, a):
    return rgb_to_hex(tuple(f * a + b * (1 - a) for f, b in zip(hex_to_rgb(fg), hex_to_rgb(bg))))


def kde_scheme(accent, name):
    n = NEUTRAL
    dim = _blend(accent, n["window"], 0.35)       # inactive selection, alt button
    common = {
        "DecorationFocus": accent, "DecorationHover": accent,
        "ForegroundActive": accent, "ForegroundInactive": n["muted"],
        "ForegroundLink": accent, "ForegroundVisited": n["visited"],
        "ForegroundNegative": n["negative"], "ForegroundNeutral": n["neutral"],
        "ForegroundPositive": n["positive"], "ForegroundNormal": n["fg"],
    }
    sets = {
        "Button": (n["raised"], dim),
        "Complementary": (n["window"], dim),
        "Header": (n["header"], n["window"]),
        "Header][Inactive": (n["header"], n["window"]),
        "Tooltip": (n["window"], n["raised"]),
        "View": (n["view"], n["window"]),
        "Window": (n["window"], n["raised"]),
    }
    out = [f"# {HEADER}\n"]
    for section, (bg, alt) in sets.items():
        out.append(f"[Colors:{section}]")
        out += [f"BackgroundNormal={_rgb(bg)}", f"BackgroundAlternate={_rgb(alt)}"]
        out += [f"{k}={_rgb(v)}" for k, v in common.items()]
        out.append("")
    # Accent is light (L 0.79), so text on it has to be dark.
    sel = dict(common, ForegroundNormal=n["window"], ForegroundActive=n["window"],
               ForegroundInactive=n["raised"], ForegroundLink=n["window"],
               ForegroundNegative="#8a1c1c", ForegroundNeutral="#6b4a00",
               ForegroundPositive="#1d5a26")
    out.append("[Colors:Selection]")
    out += [f"BackgroundNormal={_rgb(accent)}", f"BackgroundAlternate={_rgb(dim)}"]
    out += [f"{k}={_rgb(v)}" for k, v in sel.items()]
    out += ["", "[ColorEffects:Disabled]", "Color=56,56,56", "ColorAmount=0", "ColorEffect=0",
            "ContrastAmount=0.65", "ContrastEffect=1", "IntensityAmount=0.1", "IntensityEffect=2",
            "", "[ColorEffects:Inactive]", "ChangeSelectionColor=true", "Enable=false",
            "", "[General]", f"ColorScheme={name}", "Name=Rice", "shadeSortColumn=true",
            "", "[KDE]", "contrast=4",
            "", "[WM]", f"activeBackground={_rgb(n['window'])}", f"activeForeground={_rgb(n['fg'])}",
            f"activeBlend={_rgb(n['fg'])}", f"inactiveBackground={_rgb(n['header'])}",
            f"inactiveForeground={_rgb(n['muted'])}", f"inactiveBlend={_rgb(n['muted'])}", ""]
    return "\n".join(out)


def apply_kde_scheme(accent):
    """Fire-and-forget: plasma-apply-colorscheme takes a moment, and apps
    repaint on their own when they get the change signal."""
    def kread(group, key):
        return subprocess.run(["kreadconfig6", "--file", "kdeglobals", "--group", group,
                               "--key", key], capture_output=True, text=True).stdout.strip()
    try:
        cur = kread("General", "ColorScheme")
        if cur in ("RiceA", "RiceB") and kread("Colors:Selection", "BackgroundNormal") == _rgb(accent):
            return
    except OSError:  # no KDE tools installed
        return
    SCHEMES.mkdir(parents=True, exist_ok=True)
    name = "RiceB" if cur == "RiceA" else "RiceA"
    write(SCHEMES / f"{name}.colors", kde_scheme(accent, name))
    try:
        subprocess.Popen(["plasma-apply-colorscheme", name], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        print(f"theme-apply: couldn't apply KDE color scheme ({e})", file=sys.stderr)


def set_border(color):
    subprocess.run(["hyprctl", "eval",
                    f'hl.config({{ general = {{ col = {{ active_border = "rgba({color.lstrip("#")}ee)" }} }} }})'],
                   capture_output=True)


ZEN = CONFIG / "zen"
ZEN_USERJS_BEGIN = "// >>> theme-apply.py >>>"
ZEN_USERJS_END = "// <<< theme-apply.py <<<"


def zen_profiles():
    """Profiles Zen actually starts with (the [Install*] Default= entries)."""
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    try:
        cp.read(ZEN / "profiles.ini")
    except configparser.Error:
        return []
    paths = {cp[s]["Default"] for s in cp.sections() if s.startswith("Install") and "Default" in cp[s]}
    return [ZEN / p for p in sorted(paths) if (ZEN / p).is_dir()]


def zen_css(accent):
    n = NEUTRAL
    bg = n["window"]
    return f"""/* {HEADER} */
/* Zen sets these inline from the space gradient, hence !important. Read at startup only. */
:root {{
  --zen-primary-color: {accent} !important;
  --zen-branding-dark: {n["view"]} !important;
  --zen-urlbar-background: {n["view"]} !important;
  --zen-dialog-background: {bg} !important;
  --toolbox-textcolor: {n["fg"]} !important;
  --toolbar-color-scheme: dark !important;
}}
#zen-browser-background, #zen-toolbar-background {{
  --zen-main-browser-background: {bg} !important;
  --zen-main-browser-background-toolbar: {bg} !important;
  --zen-main-browser-background-old: {bg} !important;
  --zen-main-browser-background-toolbar-old: {bg} !important;
}}
.tabbrowser-tab[selected] .tab-background,
.tabbrowser-tab[multiselected] .tab-background {{
  background-color: color-mix(in srgb, {accent} 16%, transparent) !important;
}}
#urlbar[focused] #urlbar-background {{
  outline: 1px solid color-mix(in srgb, {accent} 70%, transparent) !important;
}}
::selection {{
  background-color: {accent} !important;
  color: {n["view"]} !important;
}}
"""


def zen_theme(accent):
    """Zen: accent pref in user.js + userChrome.css colors. Applied on next browser start."""
    block = (f"{ZEN_USERJS_BEGIN}\n// {HEADER}\n"
             f'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n'
             f'user_pref("zen.theme.accent-color", "{accent}");\n'
             f"{ZEN_USERJS_END}\n")
    for prof in zen_profiles():
        userjs = prof / "user.js"
        old = userjs.read_text() if userjs.exists() else ""
        if ZEN_USERJS_BEGIN in old and ZEN_USERJS_END in old:
            head, rest = old.split(ZEN_USERJS_BEGIN, 1)
            new = head + block + rest.split(ZEN_USERJS_END, 1)[1].lstrip("\n")
        else:
            new = old + ("\n" if old and not old.endswith("\n") else "") + block
        write(userjs, new)

        chrome = prof / "chrome"
        chrome.mkdir(exist_ok=True)
        write(chrome / "rice.css", zen_css(accent))
        user_chrome = chrome / "userChrome.css"
        if not user_chrome.exists():  # hand-editable; we only make sure it pulls rice.css in
            user_chrome.write_text('@import url("rice.css");\n\n/* your own tweaks below */\n')


def apply(accent, animate):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        start = CURRENT.read_text().strip()
        if not is_hex(start):
            raise ValueError
    except (OSError, ValueError):
        start = DEFAULT
    if start == accent:
        animate = False

    write_static(accent)

    if animate:
        # GTK interpolates in plain RGB, which goes gray between distant hues.
        # So Waybar gets WAYBAR_SEGMENTS linear hops between points on the same
        # eased OKLCH path the border follows; each hop starts from wherever
        # the previous one currently is, so it stays continuous.
        seg_ms = int(DURATION * 1000 / WAYBAR_SEGMENTS)
        next_seg = 0
        t0 = time.monotonic()
        while (t := (time.monotonic() - t0) / DURATION) < 1:
            if t >= next_seg / WAYBAR_SEGMENTS:
                next_seg += 1
                target = mix_oklch(start, accent, ease_in_out(next_seg / WAYBAR_SEGMENTS))
                write(CONFIG / "waybar/colors.css", waybar_css(target, seg_ms))
            color = mix_oklch(start, accent, ease_in_out(t))
            set_border(color)
            CURRENT.write_text(color)  # so an interrupting run starts from here
            time.sleep(1 / FPS)
        set_border(accent)
        CURRENT.write_text(accent)
        time.sleep(seg_ms / 1000 + 0.1)  # let GTK finish its last hop before switching transitions off
        write(CONFIG / "waybar/colors.css", waybar_css(accent))
    else:
        write(CONFIG / "waybar/colors.css", waybar_css(accent))
        set_border(accent)
        CURRENT.write_text(accent)


def take_over():
    """Only one run at a time: a newer wallpaper switch interrupts an older animation."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        old = int(PIDFILE.read_text())
        if old != os.getpid() and Path(f"/proc/{old}/cmdline").read_bytes().find(b"theme-apply") >= 0:
            os.kill(old, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    PIDFILE.write_text(str(os.getpid()))


# -- CLI -------------------------------------------------------------------------

def edit_override(name, color):
    lines = OVERRIDES.read_text().splitlines() if OVERRIDES.exists() else []
    lines = [l for l in lines if not (not l.lstrip().startswith("#") and "=" in l
                                      and l.rsplit("=", 1)[0].strip() == name)]
    if color:
        lines.append(f"{name} = {color}")
    OVERRIDES.parent.mkdir(parents=True, exist_ok=True)
    write(OVERRIDES, "\n".join(lines) + "\n")


def main():
    args = sys.argv[1:]
    animate = "--no-anim" not in args
    args = [a for a in args if a != "--no-anim"]

    if args and args[0] == "--preview":
        for f in sorted(WALLPAPERS.iterdir()):
            if f.is_file():
                acc, how = accent_for(f)
                print(f"{acc}  {how:7}  {f.name}")
        return

    if args and args[0] in ("--pin", "--unpin"):
        wp = current_wallpaper()
        if not wp:
            sys.exit("theme-apply: can't tell which wallpaper is current")
        if args[0] == "--pin":
            if len(args) < 2 or not is_hex(args[1]):
                sys.exit("usage: theme-apply.py --pin '#rrggbb'")
            edit_override(wp.name, "#" + args[1].lstrip("#").lower())
        else:
            edit_override(wp.name, None)
        args = [str(wp)]

    wp = Path(args[0]).expanduser() if args else current_wallpaper()
    if not wp or not wp.is_file():
        sys.exit(f"theme-apply: no such wallpaper: {wp}")

    take_over()
    accent, how = accent_for(wp)
    print(f"{accent} ({how}) {wp.name}")
    apply(accent, animate)


if __name__ == "__main__":
    main()
