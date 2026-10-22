import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

// Switches Quickshell grows itself (see Wallpaper.grows).
// It sits in the bottom layer, since a newly started mpvpaper lands on top of everything in the background one. Stays mapped
// at 1x1 between switches: created before the desktop widgets, it keeps below them that way.
PanelWindow {
    id: root

    readonly property bool active: Wallpaper.grows.count > 0
    readonly property real dpr: screen?.devicePixelRatio || 1
    // Hyprland's monitor, for placing the cursor; ui is the panel scale (QT_SCALE_FACTOR)
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property real ui: Number(Quickshell.env("QT_SCALE_FACTOR") || 1)
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
            required property int fx
            required property string old
            required property bool wait
            required property real px
            required property real py
            required property int ms
            required property real t0
            required property real at
            required property int dir
            required property int index
            required property int gid

            readonly property bool video: Wallpaper.isVideo(path)
            readonly property bool toReady: video ? videoLoader.playing : img.status === Image.Ready
            readonly property bool oldReady: old === "" || oldImg.status === Image.Ready || oldImg.status === Image.Error
            readonly property bool ready: toReady && oldReady && !wait

            // Starts once both ends are there
            onReadyChanged: {
                if (ready && !at)
                    Wallpaper.grows.setProperty(index, "at", Date.now());
            }

            // Newer switches on top: the Repeater doesn't keep added items above the earlier ones
            z: gid
            anchors.fill: parent
            scale: 1 + root.fxZoom
            visible: root.full

            TransitionEffect {
                anchors.fill: parent
                visible: grow.ready
                source: grow.video ? videoTexture : img
                previous: oldImg.status === Image.Ready ? oldImg : img
                hasPrevious: oldImg.status === Image.Ready
                cropTo: grow.video ? Qt.size(1, 1) : cropOf(img)
                cropFrom: cropOf(oldImg)
                t: Wallpaper.growT(grow.t0, grow.at, grow.dir, undefined, grow.ms)
                effect: grow.fx
                origin: grow.origin
                cursor: grow.px > -1e5 ? Qt.point((grow.px - (root.monitor?.x ?? 0)) / root.ui, (grow.py - (root.monitor?.y ?? 0)) / root.ui) : Qt.point(-1e6, -1e6)
            }

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
            }

            // The wallpaper it replaces, for styles that move it
            Image {
                id: oldImg

                anchors.fill: parent
                visible: false
                source: grow.old === "" ? "" : "file://" + grow.old
                sourceSize: Qt.size(root.screen.width * root.dpr, root.screen.height * root.dpr)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
            }

            Loader {
                id: videoLoader

                property bool playing: false

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
                        videoLoader.playing = true;
                    }
                }
            }

            ShaderEffectSource {
                id: videoTexture

                anchors.fill: parent
                visible: false
                sourceItem: videoLoader.item
                hideSource: true
                live: true
            }
        }
    }
}
