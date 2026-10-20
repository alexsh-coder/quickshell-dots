import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Music-reactive copy of the wallpaper on top of awww: zoom on the bass, blur and shake on kicks,
// accent glow from the bottom edge. Only mapped while music plays, so awww shows through otherwise.
PanelWindow {
    id: root

    property string source: Wallpaper.current
    // Hidden while awww runs its own transition, so that one stays visible
    property bool swapping: false
    property real time: 0

    readonly property bool active: MusicFx.wallpaperFx && Cava.active && source !== "" && !swapping
    readonly property real zoom: MusicFx.zoom ? Cava.bass * 0.04 * MusicFx.gain("zoom") : 0
    // Trauma squared, as in game screen shake, so small kicks stay subtle
    readonly property real shakeAmp: MusicFx.shake ? Cava.kick * Cava.kick * 14 * MusicFx.gain("shake") : 0

    visible: active || stage.opacity > 0

    WlrLayershell.namespace: "wallpaper-fx"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: Region {}

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            root.swapping = true;
            swap.restart();
        }
    }

    Timer {
        id: swap
        interval: 900
        onTriggered: {
            root.source = Wallpaper.current;
            root.swapping = false;
        }
    }

    FrameAnimation {
        running: root.visible && MusicFx.shake
        onTriggered: root.time += frameTime
    }

    Item {
        id: stage

        anchors.fill: parent
        clip: true
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.swapping ? 0 : Theme.anim * 2 } }

        Image {
            id: image

            anchors.fill: parent
            source: root.source ? "file://" + root.source : ""
            sourceSize: Qt.size(root.width * 1.1, root.height * 1.1)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true

            // No padding: the blur clamps at the edges instead of fading them to transparent
            layer.enabled: MusicFx.blur
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 48
                // Kicks, not loudness: a song that stays loud shouldn't keep the wallpaper blurred
                blur: Math.min(1, Cava.kick * 0.8 * MusicFx.gain("blur"))
            }

            // Overscan just enough to hide the edges while shaking
            scale: 1 + root.zoom + root.shakeAmp * 2 / Math.min(root.width, root.height)
            // Layered sines instead of random(), so the shake is jittery but not flickery
            transform: Translate {
                x: root.shakeAmp * (Math.sin(root.time * 47) * 0.6 + Math.sin(root.time * 83 + 1.3) * 0.4)
                y: root.shakeAmp * (Math.sin(root.time * 53 + 2.1) * 0.6 + Math.sin(root.time * 71 + 0.4) * 0.4)
            }
        }

        Rectangle {
            visible: MusicFx.glow
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * 0.45
            opacity: Math.min(1, Cava.bass * 0.9 * MusicFx.gain("glow"))
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.alpha(Theme.accent, 0.35) }
            }
        }
    }
}
