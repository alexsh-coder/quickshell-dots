pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property color accent: "#33ccff"
    readonly property color bg: "#0d1117"
    readonly property color surface: "#161c24"
    readonly property color text: "#e6edf3"
    readonly property color subtext: "#8b949e"
    readonly property color muted: "#30363d"
    readonly property color urgent: "#ff6b81"

    readonly property string font: "Maple Mono"
    readonly property string nerdFont: "CaskaydiaCove Nerd Font"
    readonly property string iconFont: "Material Symbols Rounded"

    readonly property int barHeight: 42
    readonly property int radius: 12
    readonly property int anim: 220
    readonly property int osdMargin: 56
}
