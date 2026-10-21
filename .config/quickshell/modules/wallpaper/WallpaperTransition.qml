import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The still a video wallpaper is revealed from (see Wallpaper.cover). It sits in the bottom layer,
// since a newly started mpvpaper lands on top of everything in the background one. Stays mapped
// at 1x1 between switches: created before the desktop widgets, it keeps below them that way.
PanelWindow {
    id: root

    readonly property bool active: Wallpaper.cover !== ""
    readonly property real dpr: screen?.devicePixelRatio || 1
    // Drawn only once at full size: a layer made while still 1x1 stretches one pixel over the screen
    readonly property bool full: active && width >= screen.width && height >= screen.height
    readonly property bool shown: full && still.status === Image.Ready

    WlrLayershell.namespace: "wallpaper-transition"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        left: true
        bottom: active
        right: active
    }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    mask: Region {}

    // A couple of frames for the still to reach the screen before the player may show up under it
    onShownChanged: {
        if (shown)
            settle.restart();
    }

    Timer {
        id: settle
        interval: 50
        onTriggered: {
            if (root.shown)
                Wallpaper.coverShown();
        }
    }

    Image {
        id: still

        anchors.fill: parent
        visible: root.full
        // Holds the wallpaper's still between switches, so the usual cover is up at once
        source: (Wallpaper.cover || Wallpaper.image) ? "file://" + (Wallpaper.cover || Wallpaper.image) : ""
        sourceSize: Qt.size(root.screen.width * root.dpr, root.screen.height * root.dpr)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true

        layer.enabled: root.full
        layer.effect: ShaderEffect {
            readonly property real radius: Wallpaper.reveal * Math.hypot(width / 2, height)
            readonly property point center: Qt.point(width / 2, height)
            readonly property size extent: Qt.size(width, height)

            fragmentShader: Qt.resolvedUrl("../../shaders/reveal.frag.qsb")
        }
    }
}
