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
    readonly property color bg: Scheme.pick("#ffffff", "#0d1117")
    readonly property color surface: Scheme.pick("#f6f8fa", "#161c24")
    readonly property color text: Scheme.pick("#1f2328", "#e6edf3")
    readonly property color subtext: Scheme.pick("#59636e", "#8b949e")
    readonly property color muted: Scheme.pick("#d1d9e0", "#30363d")
    readonly property color urgent: Scheme.pick("#cf222e", "#ff6b81")
    // Bar's left pill: M3-style neutrals carrying the accent hue,
    // with the accent held to the chroma of soft anime/pastel wallpapers
    readonly property color tintAccent: Scheme.pick(Accent.role(0.63, 0.14, 0, 0.14), Accent.color)
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
}
