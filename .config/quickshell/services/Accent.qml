pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Accent from the wallpaper, normalized to the house look (#33ccff is OKLCH L 0.79 C 0.14):
// same lightness for every wallpaper, chroma kept in a vivid-but-not-neon band
Singleton {
    id: root

    readonly property color fallback: "#33ccff"
    readonly property real targetL: 0.79
    // Light scheme: dark enough for 4.5:1 on white across hues
    readonly property real lightL: 0.6
    readonly property real minC: 0.12
    readonly property real maxC: 0.17
    // Source colors below this chroma don't count as a hue
    readonly property real grayC: 0.035

    readonly property color base: mix(from, to, progress)
    // Wallpaper tweaks apply on top: hue and chroma to every role, lightness to the accent itself
    readonly property color tunedBase: shift(base, tweak.h, tweak.c, 0)
    // Grayscale wallpaper: no hue to take, so the accent is black or white against the bar
    property bool gray: false
    readonly property bool mono: Wallpaper.mono || gray
    readonly property color monoLight: "#1a1a1a"
    readonly property color monoDark: "#f2f2f2"
    // Drawn straight on the wallpaper (visualizers): a grayscale one gets the opposite of its own brightness
    property bool wallLight: false
    readonly property color onWall: mono ? (wallLight ? monoLight : monoDark) : color
    readonly property color color: mono ? Scheme.pick(monoLight, monoDark) : Scheme.dark >= 1 ? shift(tunedBase, 0, 0, tweak.l) : lightAccent(tunedBase, lightL + (tweak.l || 0) + (targetL - lightL) * Scheme.dark)
    // M3-style roles: secondary is a muted accent, tertiary sits 60° away in hue
    readonly property color secondary: role(0.5 + 0.34 * Scheme.dark, 0.05, 0)
    readonly property color tertiary: role(0.56 + 0.26 * Scheme.dark, 0.1 + 0.07 * (1 - Scheme.dark), -60 + 120 * Scheme.dark)

    // Colour balance of the wallpaper: [{ w: share, h: OKLCH hue }], biggest first.
    // Gray, white and black don't count, close hues are merged, minor ones dropped
    property var palette: []
    readonly property real mergeHue: 30
    readonly property real minShare: 0.1

    function lightAccent(c0, L) {
        const [l, c, h] = toOklch(c0);
        return fromOklch(L, Math.max(c, 0.19 + (tweak.c || 0)), h);
    }

    function role(L, C, shift, cap) {
        const [l, c, h] = toOklch(tunedBase);
        return fromOklch(L, mono ? 0 : Math.min(C, Math.max(c, cap || 0)), (h + shift + 360) % 360);
    }

    // Per-wallpaper nudges in OKLCH, keyed by wallpaper path, then by scope (both, light, dark):
    // { h, c, l } for the accent, { bh, bc, bl } for the bar on top of it.
    // The active value is both + the current scheme's own
    property var tweaks: ({})
    readonly property var tweak: tweakFor(Scheme.light ? "light" : "dark")
    readonly property var tweakDark: tweakFor("dark")

    function tweakFor(mode) {
        const t = tweaks[Wallpaper.current] || {};
        const a = t.both || {}, b = t[mode] || {};
        const out = {};
        for (const k of ["h", "c", "l", "bh", "bc", "bl"])
            out[k] = (a[k] || 0) + (b[k] || 0);
        return out;
    }

    function scopeTweak(scope) {
        return (tweaks[Wallpaper.current] || {})[scope] || {};
    }
    function shift(c, dh, dc, dl) {
        if (!dh && !dc && !dl)
            return c;
        const [L, C, H] = toOklch(c);
        return fromOklch(Math.max(0, Math.min(1, L + (dl || 0))), Math.max(0, C + (dc || 0)), (H + (dh || 0) + 360) % 360);
    }

    readonly property color barColor: shift(color, tweak.bh, tweak.bc, tweak.bl)

    function barRole(c) {
        return shift(c, tweak.bh, tweak.bc, tweak.bl);
    }

    // Live edit from the picker: jumps straight to the result instead of fading
    function setTweak(scope, key, value) {
        const path = Wallpaper.current;
        if (!path)
            return;
        const t = Object.assign({}, tweaks[path] || {});
        const s = Object.assign({}, t[scope] || {});
        if (value)
            s[key] = value;
        else
            delete s[key];
        if (Object.keys(s).length)
            t[scope] = s;
        else
            delete t[scope];
        const all = Object.assign({}, tweaks);
        if (Object.keys(t).length)
            all[path] = t;
        else
            delete all[path];
        tweaks = all;
        tweakFile.setText(JSON.stringify(all, null, 1));
    }

    property color from: fallback
    property color to: fallback
    property real progress: 1

    property string wanted: ""
    property string sources: ""
    property string ranFor: ""

    function pick(path) {
        wanted = path;
        if (path && !matugen.running) {
            ranFor = path;
            matugen.command = ["matugen", "image", path, "--show-source-colors"];
            matugen.running = true;
        }
    }

    function fade(next) {
        if (Qt.colorEqual(next, to))
            return;
        from = base;
        to = next;
        progress = 0;
        anim.restart();
        saved.setText(next.toString());
    }

    // Mean OKLCH lightness of a histogram
    function brightness(text) {
        const re = /(\d+):.*?(#[0-9a-fA-F]{6})/g;
        let m, n = 0, sum = 0;
        while ((m = re.exec(text))) {
            n += +m[1];
            sum += +m[1] * toOklch(Qt.color(m[2]))[0];
        }
        return n ? sum / n : 0;
    }

    // Parses an ImageMagick histogram ("count: (r,g,b) #hex ..." per line)
    function weigh(text) {
        const bins = [];
        const re = /(\d+):.*?(#[0-9a-fA-F]{6})/g;
        let m;
        while ((m = re.exec(text)))
            bins.push([+m[1], m[2]]);
        bins.sort((a, b) => b[0] - a[0]);
        const groups = [];
        for (const [count, hex] of bins) {
            const [L, C, H] = toOklch(Qt.color(hex));
            if (C < grayC)
                continue;
            let g = groups.find(g => Math.abs((Math.atan2(g.y, g.x) * 180 / Math.PI - H + 540) % 360 - 180) < mergeHue);
            if (!g)
                groups.push(g = { w: 0, x: 0, y: 0 });
            g.w += count;
            g.x += count * Math.cos(H * Math.PI / 180);
            g.y += count * Math.sin(H * Math.PI / 180);
        }
        const total = groups.reduce((s, g) => s + g.w, 0);
        const kept = groups.filter(g => g.w >= total * minShare).sort((a, b) => b.w - a.w);
        const sum = kept.reduce((s, g) => s + g.w, 0);
        return kept.map(g => ({ w: g.w / sum, h: (Math.atan2(g.y, g.x) * 180 / Math.PI + 360) % 360 }));
    }

    function fromSources(text) {
        for (const hex of text.match(/#[0-9a-fA-F]{6}\b/g) || []) {
            const [L, C, H] = toOklch(Qt.color(hex));
            if (C >= grayC)
                return fromOklch(targetL, Math.min(Math.max(C, minC), maxC), H);
        }
        return fallback;
    }

    // Most saturated in-gamut colour of a hue, at the lightness where it is juiciest but never dark:
    // yellow peaks near 0.9, blue near 0.72
    function neon(H) {
        let best = [0.72, 0, H];
        for (let L = 0.72; L <= 0.9; L += 0.02) {
            let lo = 0, hi = 0.4;
            for (let i = 0; i < 16; i++) {
                const mid = (lo + hi) / 2;
                rawRgb(L, mid, H).every(c => c >= -1e-4 && c <= 1 + 1e-4) ? lo = mid : hi = mid;
            }
            if (lo > best[1])
                best = [L, lo, H];
        }
        return best;
    }

    // Interpolates in OKLCH so distant hues don't pass through gray
    function mix(a, b, t) {
        if (t >= 1)
            return b;
        const [L1, C1, H1] = toOklch(a);
        const [L2, C2, H2] = toOklch(b);
        const dh = ((H2 - H1 + 540) % 360) - 180;
        return fromOklch(L1 + (L2 - L1) * t, C1 + (C2 - C1) * t, H1 + dh * t);
    }

    function lin(c) {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function gam(c) {
        return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
    }

    function toOklch(c) {
        const r = lin(c.r), g = lin(c.g), b = lin(c.b);
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, Math.hypot(A, B), (Math.atan2(B, A) * 180 / Math.PI + 360) % 360];
    }

    function rawRgb(L, C, H) {
        const a = C * Math.cos(H * Math.PI / 180), b = C * Math.sin(H * Math.PI / 180);
        const l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
        const m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
        const s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
        return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
    }

    // Gamut-maps by reducing chroma until the color fits in sRGB
    function fromOklch(L, C, H) {
        const fits = rgb => rgb.every(c => c >= -1e-4 && c <= 1 + 1e-4);
        let rgb = rawRgb(L, C, H);
        if (!fits(rgb)) {
            let lo = 0, hi = C;
            for (let i = 0; i < 20; i++) {
                const mid = (lo + hi) / 2;
                fits(rawRgb(L, mid, H)) ? lo = mid : hi = mid;
            }
            rgb = rawRgb(L, lo, H);
        }
        const [r, g, b] = rgb.map(c => gam(Math.min(1, Math.max(0, c))));
        return Qt.rgba(r, g, b, 1);
    }

    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        from: 0
        to: 1
        // Matches the awww transition
        duration: 800
        easing.type: Easing.InOutSine
    }

    Process {
        id: matugen
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.ranFor === root.wanted) {
                    root.sources = text;
                    histogram.exec(["magick", root.ranFor, "-resize", "128x128", "-colors", "12", "-depth", "8", "-format", "%c", "histogram:info:-"]);
                } else
                    root.pick(root.wanted);
            }
        }
    }

    Process {
        id: histogram
        stdout: StdioCollector {
            // matugen falls back to Google blue on gray images, so the histogram decides
            onStreamFinished: {
                root.palette = root.weigh(text);
                root.wallLight = root.brightness(text) > 0.5;
                root.gray = root.palette.length === 0;
                root.fade(root.mono ? root.monoDark : root.fromSources(root.sources));
            }
        }
    }

    // Last accent, so the shell starts in it instead of flashing the fallback
    FileView {
        id: saved
        path: Quickshell.statePath("accent")
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: tweakFile
        path: Quickshell.statePath("accent-tweaks.json")
        blockLoading: true
        printErrors: false
    }

    Connections {
        target: Wallpaper
        function onImageChanged() {
            root.pick(Wallpaper.image);
        }
    }

    // Hyprland window border follows the accent, and survives `hyprctl reload`
    readonly property bool hyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    property bool borderDirty: false

    function pushBorder() {
        if (!hyprland)
            return;
        if (border.running) {
            borderDirty = true;
            return;
        }
        const hex = color.toString().slice(1);
        border.command = ["hyprctl", "eval", `hl.config({ general = { col = { active_border = "rgba(${hex}ee)" } } })`];
        border.running = true;
    }

    onColorChanged: pushBorder()

    Process {
        id: border
        onExited: {
            if (root.borderDirty) {
                root.borderDirty = false;
                root.pushBorder();
            }
        }
    }

    Connections {
        target: Hyprland
        enabled: root.hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.pushBorder();
        }
    }

    // kitty follows the dark-scheme accent, its background stays dark either way.
    // ANSI hues are pulled 30% toward the accent; green and blue are the accent itself,
    // so cmatrix and friends draw in it
    readonly property var ansiHues: ({ 1: 25, 3: 90, 5: 330, 6: 200 })
    property bool kittyDirty: false

    function kittyColors(accent) {
        const hex = accent.toString();
        const ha = toOklch(accent)[2];
        const out = [["cursor", hex], ["selection_background", hex]];
        for (const n of [2, 4, 10, 12])
            out.push([`color${n}`, hex]);
        for (const [n, h0] of Object.entries(ansiHues)) {
            const h = h0 + ((ha - h0 + 540) % 360 - 180) * 0.3;
            out.push([`color${n}`, fromOklch(0.7, 0.1, h).toString()], [`color${+n + 8}`, fromOklch(0.8, 0.09, h).toString()]);
        }
        return out;
    }

    function pushKitty() {
        if (kitty.running) {
            kittyDirty = true;
            return;
        }
        const colors = kittyColors(shift(to, tweakDark.h, tweakDark.c, tweakDark.l));
        kittyConf.setText("# Generated by Quickshell (services/Accent.qml) on wallpaper change\n" + colors.map(([k, v]) => `${k} ${v}\n`).join(""));
        // kitty suffixes its listen_on socket with -<pid>, one per instance
        kitty.command = ["sh", "-c", 'for p in $(pgrep -x kitty); do kitty @ --to "unix:@kitty-$p" set-colors -a -c "$@"; done', "sh", ...colors.map(([k, v]) => `${k}=${v}`)];
        kitty.running = true;
    }

    onToChanged: pushKitty()
    onTweakDarkChanged: pushKitty()

    // Included from kitty.conf, so new windows start in the accent too
    FileView {
        id: kittyConf
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kitty/theme-colors.conf"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: kitty
        onExited: {
            if (root.kittyDirty) {
                root.kittyDirty = false;
                root.pushKitty();
            }
        }
    }

    // KDE/Qt apps (Dolphin etc. via QT_QPA_PLATFORMTHEME=kde) and GTK apps take the settled accent,
    // not every frame of the fade: each apply repaints all of them
    readonly property color settled: mono ? (Scheme.light ? monoLight : monoDark) : Scheme.light ? lightAccent(shift(to, tweak.h, tweak.c, 0), lightL + tweak.l) : shift(to, tweak.h, tweak.c, tweak.l)
    property bool kdeDirty: false

    function pushKde() {
        if (kde.running) {
            kdeDirty = true;
            return;
        }
        const c = settled;
        const rgb = [c.r, c.g, c.b].map(v => Math.round(v * 255)).join(",");
        // AccentColor with --notify makes kded's gtkconfig regenerate GTK colors.css,
        // which Firefox/Zen read as the system AccentColor.
        // With -a plasma-apply-colorscheme only sets the accent and ignores the scheme name,
        // so the scheme goes in a separate call first.
        // It signals the palette change before kdeglobals is written,
        // so running Qt apps (Telegram etc.) reload the old colors; signal again once it's on disk
        kde.command = ["sh", "-c", 'plasma-apply-colorscheme "$2" && plasma-apply-colorscheme -a "$1" && kwriteconfig6 --file kdeglobals --group General --key AccentColor --notify "$3" && dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0', "sh", c.toString(), Scheme.light ? "BreezeLight" : "BreezeDark", rgb];
        kde.running = true;
    }

    onSettledChanged: pushKde()

    Process {
        id: kde
        onExited: {
            if (root.kdeDirty) {
                root.kdeDirty = false;
                root.pushKde();
            }
        }
    }

    Component.onCompleted: {
        try {
            const all = JSON.parse(tweakFile.text() || "{}");
            // Flat entries predate scopes and mean both
            for (const p in all)
                if (!all[p].both && !all[p].light && !all[p].dark)
                    all[p] = { both: all[p] };
            tweaks = all;
        } catch (e) {}
        const last = saved.text().trim();
        if (/^#[0-9a-fA-F]{6}$/.test(last))
            from = to = last;
        pushBorder();
        pushKitty();
        pushKde();
        pick(Wallpaper.image);
    }
}
