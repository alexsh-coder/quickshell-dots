import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Catches clicks on the empty desktop: windows and desktop widgets sit above it, so only bare wallpaper reaches it.
// Always mapped and switched by its mask: a layer mapped later would land above the desktop widgets
PanelWindow {
    id: root

    readonly property bool on: Settings.clickToChange && Settings.transitionFrom === "cursor"

    WlrLayershell.namespace: "desk-click"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // 1x1 while off, like WallpaperTransition: stays in place in the stack without full-screen buffers
    anchors {
        top: true
        left: true
        bottom: root.on
        right: root.on
    }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    mask: Region { item: root.on ? catcher : null }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: Wallpaper.randomRequested()
    }
}
