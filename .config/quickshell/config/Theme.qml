pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    readonly property color accent: Accent.color
    readonly property color secondary: Accent.secondary
    readonly property color tertiary: Accent.tertiary
    // Dark is GitHub Dark-based, light follows GitHub Primer light
    readonly property bool light: Scheme.light
    readonly property color bg: Scheme.pick("#ffffff", Accent.mono ? "#0d0d0d" : "#0d1117")
    readonly property color surface: Scheme.pick(Accent.mono ? "#f2f2f2" : "#f6f8fa", Accent.mono ? "#1a1a1a" : "#161c24")
    readonly property color text: Scheme.pick("#1f2328", "#e6edf3")
    readonly property color subtext: Scheme.pick("#59636e", "#8b949e")
    readonly property color muted: Scheme.pick("#d1d9e0", "#30363d")
    readonly property color urgent: Scheme.pick("#cf222e", "#ff6b81")
    // Bar's left pill: M3-style neutrals carrying the accent hue,
    // with the accent held to the chroma of soft anime/pastel wallpapers
    readonly property color tintAccent: Accent.mono ? Accent.color : Accent.barRole(Scheme.pick(Accent.role(0.63 + Accent.tweak.l, 0.14 + Accent.tweak.c, 0, 0.14 + Accent.tweak.c), Accent.color))
    // Accent for the bar, with the wallpaper's own bar tweak on top
    readonly property color wallAccent: Accent.onWall
    // Music effects: the wallpaper's own contrast color unless the preset picks another
    readonly property color fxColor: hueShift(paint(MusicFx.color))
    readonly property color barAccent: Accent.barColor
    readonly property color tintSubtext: Scheme.pick(Accent.role(0.71, 0.06, 0, 0.06), Accent.role(0.6, 0.045, 0, 0.045))
    readonly property color tintMuted: Scheme.pick(Accent.role(0.875, 0.035, 0, 0.035), Accent.role(0.36, 0.03, 0, 0.03))
    // Halo behind text drawn straight on the wallpaper
    readonly property color halo: Scheme.pick("#ffffff", "#000000")

    readonly property string font: "Maple Mono"
    readonly property string nerdFont: "CaskaydiaCove Nerd Font"
    readonly property string iconFont: "Material Symbols Rounded"

    readonly property string terminal: "kitty"

    readonly property int barHeight: 42
    readonly property int barIcon: 20
    readonly property int radius: 12
    // Popout padding; the top is tighter since the panel continues the bar
    readonly property int pad: 18
    readonly property int padTop: 14
    readonly property int anim: 220

    // Material 3 motion curves, for Easing.BezierSpline
    readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
    // M3 emphasized: quick lift-off, long soft landing, no overshoot
    readonly property list<real> emphasized: [0.05, 0, 0.133, 0.06, 0.167, 0.4, 0.208, 0.82, 0.25, 1, 1, 1]
    readonly property int animPanel: 450
    // M3 Expressive spatial: settles with a slight overshoot
    readonly property list<real> spatial: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property int animSpatial: 500
    readonly property int osdMargin: 56

    // A widget's color setting: "auto" is the wallpaper's own contrast color
    // The Hue effect's rotation (WallFx), the same as the wallpaper gets in wallfx.frag, for colors drawn over it
    function hueShift(c) {
        const a = WallFx.hue * WallFx.tint;
        if (!a)
            return c;
        const s = Math.sin(a) * 0.57735, co = Math.cos(a), grey = (c.r + c.g + c.b) / 3 * (1 - co);
        const f = v => Math.max(0, Math.min(1, v));
        return Qt.rgba(f(c.r * co + (c.b - c.g) * s + grey), f(c.g * co + (c.r - c.b) * s + grey), f(c.b * co + (c.g - c.r) * s + grey), c.a);
    }

    function paint(name) {
        return ({ accent: Accent.color, white: "#ffffff", black: "#000000" })[name] ?? Accent.onWall;
    }
}
