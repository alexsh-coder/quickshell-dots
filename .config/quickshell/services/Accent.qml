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
    readonly property real minC: 0.12
    readonly property real maxC: 0.17
    // Source colors below this chroma don't count as a hue
    readonly property real grayC: 0.035

    readonly property color color: mix(from, to, progress)

    property color from: fallback
    property color to: fallback
    property real progress: 1

    property string wanted: ""
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
        from = color;
        to = next;
        progress = 0;
        anim.restart();
        saved.setText(next.toString());
    }

    function fromSources(text) {
        for (const hex of text.match(/#[0-9a-fA-F]{6}\b/g) || []) {
            const [L, C, H] = toOklch(Qt.color(hex));
            if (C >= grayC)
                return fromOklch(targetL, Math.min(Math.max(C, minC), maxC), H);
        }
        return fallback;
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
                if (root.ranFor === root.wanted)
                    root.fade(root.fromSources(text));
                else
                    root.pick(root.wanted);
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

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            root.pick(Wallpaper.current);
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

    Component.onCompleted: {
        const last = saved.text().trim();
        if (/^#[0-9a-fA-F]{6}$/.test(last))
            from = to = last;
        pushBorder();
        pick(Wallpaper.current);
    }
}
