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
    anchors {
        top: true
        left: true
        bottom: true
        right: true
    }
    color: "transparent"
    mask: Region { item: root.on ? catcher : null }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: Wallpaper.randomRequested()
    }
}
