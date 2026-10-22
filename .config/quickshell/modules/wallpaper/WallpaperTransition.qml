import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.services

// Switches Quickshell grows itself (see Wallpaper.grows).
// It sits in the bottom layer, since a newly started mpvpaper lands on top of everything in the background one. Stays mapped
// at 1x1 between switches: created before the desktop widgets, it keeps below them that way.
PanelWindow {
    id: root

    readonly property bool active: Wallpaper.grows.count > 0
    readonly property real dpr: screen?.devicePixelRatio || 1
    // Drawn only once at full size: a layer made while still 1x1 stretches one pixel over the screen
    readonly property bool full: active && width >= screen.width && height >= screen.height

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

    // The bass zoom WallpaperFx puts on the wallpaper under the grows, so they match it
    readonly property real fxZoom: MusicFx.wallpaperFx && MusicFx.zoom && Cava.active && !Wallpaper.video ? Cava.bass * 0.04 * MusicFx.gain("zoom") : 0

    // Grows advance with the frames this screen draws, not on a timer that drifts against them
    FrameAnimation {
        running: Wallpaper.grows.count > 0
        onTriggered: Wallpaper.clock = Date.now()
    }

    // Switches stacking up (see Wallpaper.grows). An image's shader reads it directly:
    // no offscreen layer to allocate on every switch
    Repeater {
        model: Wallpaper.grows

        Item {
            id: grow

            required property string path
            required property string origin
            required property real t0
            required property real at
            required property int dir
            required property int index
            required property int gid

            readonly property bool video: Wallpaper.isVideo(path)
            readonly property bool side: origin !== "bottom"
            readonly property real radius: Wallpaper.grown(t0, at, dir) * (side ? Math.hypot(width, height / 2) : Math.hypot(width / 2, height))
            readonly property point center: side ? Qt.point(origin === "left" ? 0 : width, height / 2) : Qt.point(width / 2, height)

            function loaded() {
                if (!at)
                    Wallpaper.grows.setProperty(index, "at", Date.now());
            }

            // Newer switches on top: the Repeater doesn't keep added items above the earlier ones
            z: gid
            anchors.fill: parent
            scale: 1 + root.fxZoom
            visible: root.full

            ShaderEffect {
                readonly property Image source: img
                readonly property real radius: grow.radius
                readonly property point center: grow.center
                readonly property size extent: Qt.size(width, height)
                // The shader gets the whole decoded image, not the cropped part the Image would draw
                readonly property size crop: Qt.size(Math.min(1, width / Math.max(1, img.paintedWidth)), Math.min(1, height / Math.max(1, img.paintedHeight)))

                anchors.fill: parent
                visible: !grow.video && img.status === Image.Ready
                fragmentShader: Qt.resolvedUrl("../../shaders/wallgrow.frag.qsb")

                Image {
                    id: img

                    anchors.fill: parent
                    visible: false
                    source: grow.video ? "" : "file://" + grow.path
                    sourceSize: Qt.size(root.screen.width * root.dpr, root.screen.height * root.dpr)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    onStatusChanged: {
                        if (status === Image.Ready)
                            grow.loaded();
                    }
                }
            }

            Loader {
                anchors.fill: parent
                active: grow.video

                sourceComponent: Video {
                    source: "file://" + grow.path
                    fillMode: VideoOutput.PreserveAspectCrop
                    loops: MediaPlayer.Infinite
                    muted: true
                    autoPlay: true
                    onPositionChanged: {
                        if (position <= 0)
                            return;
                        Wallpaper.grows.setProperty(grow.index, "pos", position);
                        Wallpaper.grows.setProperty(grow.index, "dur", duration);
                        grow.loaded();
                    }

                    layer.enabled: true
                    layer.effect: ShaderEffect {
                        readonly property real radius: grow.radius
                        readonly property point center: grow.center
                        readonly property size extent: Qt.size(width, height)
                        readonly property size crop: Qt.size(1, 1)

                        fragmentShader: Qt.resolvedUrl("../../shaders/wallgrow.frag.qsb")
                    }
                }
            }
        }
    }
}
