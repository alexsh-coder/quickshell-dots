pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    readonly property color accent: Accent.color
    readonly property color secondary: Accent.secondary
    readonly property color tertiary: Accent.tertiary
    readonly property color bg: "#0d1117"
    readonly property color surface: "#161c24"
    readonly property color text: "#e6edf3"
    readonly property color subtext: "#8b949e"
    readonly property color muted: "#30363d"
    readonly property color urgent: "#ff6b81"

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
