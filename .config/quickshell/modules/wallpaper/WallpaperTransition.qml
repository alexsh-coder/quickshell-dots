import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.modules.musicfx
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
    // Over a video, the zoom and shake VideoFx gives mpv, so the copy moves the same until the player
    // under it takes over (same curves, in pixels)
    readonly property bool videoFx: (MusicFx.zoom || MusicFx.shake) && Cava.active && Wallpaper.video
    readonly property real shakeAmp: videoFx && MusicFx.shake ? Cava.kick * Cava.kick * 14 * MusicFx.gain("shake") : 0
    readonly property real videoZoom: videoFx ? (MusicFx.zoom ? Cava.bass * 0.04 * MusicFx.gain("zoom") : 0) + shakeAmp * 2 / Math.min(width, height) : 0
    readonly property real shakeTime: Wallpaper.clock / 1000
    readonly property real panX: shakeAmp * (Math.sin(shakeTime * 47) * 0.6 + Math.sin(shakeTime * 83 + 1.3) * 0.4)
    readonly property real panY: shakeAmp * (Math.sin(shakeTime * 53 + 2.1) * 0.6 + Math.sin(shakeTime * 71 + 0.4) * 0.4)

    // Grows advance with the frames this screen draws, not on a timer that drifts against them
    FrameAnimation {
        running: Wallpaper.grows.count > 0
        onTriggered: Wallpaper.clock = Date.now()
    }

    // WallpaperFx's glow, which the grows would cover from below until one has covered the screen
    readonly property bool glowOver: active && !Wallpaper.video

    // WallpaperFx's shader effects (bloom, pulse, hue, the glitch...) on the grows too, so a new wallpaper
    // doesn't come in plain until one has covered the screen
    WallFxStage {
        anchors.fill: parent
        on: root.full && root.glowOver && MusicFx.wallpaperFx

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
                scale: 1 + root.fxZoom + root.videoZoom
                transform: Translate { x: root.panX; y: root.panY }
                visible: root.full

                // WallpaperFx's kick blur, which the grows would otherwise hide until one covers the screen
                layer.enabled: root.glowOver && MusicFx.wallpaperFx && MusicFx.blur && Cava.active
                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 48
                    blur: Math.min(1, Cava.kick * 0.8 * MusicFx.gain("blur"))
                }

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
                    layer.enabled: active && Wallpaper.bw
                    layer.effect: MultiEffect {
                        saturation: -1
                    }

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

    Item {
        anchors.fill: parent
        z: 1e9
        visible: root.full && root.glowOver

        GlowOverlay {
            anchors.fill: parent
            strength: MusicFx.wallpaperFx && MusicFx.glow && Cava.active ? Math.min(1, Cava.bass * 0.9 * MusicFx.gain("glow")) : 0
        }
    }
}
