import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The still a video wallpaper is revealed from (see Wallpaper.cover). It sits in the bottom layer,
// since a newly started mpvpaper lands on top of everything in the background one. Stays mapped
// at 1x1 between switches: created before the desktop widgets, it keeps below them that way.
PanelWindow {
    id: root

    readonly property bool active: Wallpaper.cover !== "" || Wallpaper.grows.count > 0
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
        visible: root.full && Wallpaper.cover !== ""
        // Holds the wallpaper's still between switches, so the usual cover is up at once
        source: (Wallpaper.cover || Wallpaper.image) ? "file://" + (Wallpaper.cover || Wallpaper.image) : ""
        sourceSize: Qt.size(root.screen.width * root.dpr, root.screen.height * root.dpr)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true

        layer.enabled: root.full
        layer.effect: ShaderEffect {
            readonly property bool side: Wallpaper.origin !== "bottom"
            readonly property real radius: Wallpaper.reveal * (side ? Math.hypot(width, height / 2) : Math.hypot(width / 2, height))
            readonly property point center: side ? Qt.point(Wallpaper.origin === "left" ? 0 : width, height / 2) : Qt.point(width / 2, height)
            readonly property size extent: Qt.size(width, height)

            fragmentShader: Qt.resolvedUrl("../../shaders/reveal.frag.qsb")
        }
    }

    // The bass zoom WallpaperFx puts on the wallpaper under the grows, so they match it
    readonly property real fxZoom: MusicFx.wallpaperFx && MusicFx.zoom && Cava.active && !Wallpaper.video ? Cava.bass * 0.04 * MusicFx.gain("zoom") : 0

    // Grows advance with the frames this screen draws, not on a timer that drifts against them
    FrameAnimation {
        running: Wallpaper.grows.count > 0
        onTriggered: Wallpaper.clock = Date.now()
    }

    // Side switches stacking up (see Wallpaper.grows). The shader reads the image directly:
    // no offscreen layer to allocate on every switch
    Repeater {
        model: Wallpaper.grows

        ShaderEffect {
            id: grow

            required property string path
            required property string origin
            required property real t0
            required property real at
            required property int dir
            required property int index
            required property int gid

            readonly property Image source: img
            readonly property real radius: Wallpaper.grown(t0, at, dir) * Math.hypot(width, height / 2)
            readonly property point center: Qt.point(origin === "left" ? 0 : width, height / 2)
            readonly property size extent: Qt.size(width, height)
            // The shader gets the whole decoded image, not the cropped part the Image would draw
            readonly property size crop: Qt.size(Math.min(1, width / Math.max(1, img.paintedWidth)), Math.min(1, height / Math.max(1, img.paintedHeight)))

            // Newer switches on top: the Repeater doesn't keep added items above the earlier ones
            z: gid
            anchors.fill: parent
            scale: 1 + root.fxZoom
            visible: root.full && img.status === Image.Ready
            fragmentShader: Qt.resolvedUrl("../../shaders/wallgrow.frag.qsb")

            Image {
                id: img

                anchors.fill: parent
                visible: false
                source: "file://" + grow.path
                sourceSize: Qt.size(root.screen.width * root.dpr, root.screen.height * root.dpr)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                onStatusChanged: {
                    if (status === Image.Ready && !grow.at)
                        Wallpaper.grows.setProperty(grow.index, "at", Date.now());
                }
            }
        }
    }
}
