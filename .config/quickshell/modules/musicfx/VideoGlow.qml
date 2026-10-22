import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// WallpaperFx's accent glow over a video wallpaper, which mpvpaper draws above the background
// layer. Stays mapped at 1x1 like WallpaperTransition, so it keeps below the desktop visualizer.
PanelWindow {
    id: root

    readonly property bool active: MusicFx.glow && Cava.active && Wallpaper.video
    readonly property bool full: active || glow.shown > 0

    WlrLayershell.namespace: "wallpaper-glow"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        bottom: true
        top: full
        right: full
    }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    mask: Region {}

    GlowOverlay {
        id: glow

        property real shown: root.active ? Math.min(1, Cava.bass * 0.9 * MusicFx.gain("glow")) : 0

        anchors.fill: parent
        strength: shown
        Behavior on shown {
            enabled: !root.active
            NumberAnimation { duration: Theme.anim * 2 }
        }
    }
}
