import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Flashes a transparent layer under the pointer after a theme change: leaving it makes the
// window below set its cursor shape again, so the new theme shows without moving the mouse
PanelWindow {
    visible: Cursor.kicking
    WlrLayershell.namespace: "cursorkick"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    // The new theme's arrow (what most of the screen shows anyway); without a shape of its own
    // Hyprland would show its built-in one
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
    }
}
