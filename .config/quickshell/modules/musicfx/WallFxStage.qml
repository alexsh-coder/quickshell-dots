import QtQuick
import QtQuick.Effects
import qs.services

// The shader effects over a wallpaper, on whatever is put inside: pulse, ripple, bloom, VHS and hue (WallFx)
// with the glitch over them. Used by WallpaperFx's copy and by the grows of a switch, so a new wallpaper
// comes in with the effects already on
Item {
    id: root

    default property alias content: scene.data
    // Off while there's nothing worth a layer, e.g. the grows window sitting at 1x1
    property bool on: true

    Item {
        id: glitchHost

        anchors.fill: parent

        readonly property real burst: Glitch.burstFor("wall")

        layer.enabled: root.on && Glitch.has("wall") && (Glitch.split > 0 || burst > 0)
        layer.effect: ShaderEffect {
            property real split: Glitch.split
            property real burst: glitchHost.burst
            property real seed: Glitch.seed
            property real tear: 60 * Glitch.gain
            property real styles: 1
            property size px: Qt.size(1 / width, 1 / height)
            fragmentShader: Qt.resolvedUrl("../../shaders/glitch.frag.qsb")
        }

        Item {
            id: fxHost

            anchors.fill: parent
            layer.enabled: root.on && WallFx.on
            layer.effect: ShaderEffect {
                property real pulse: WallFx.pulse
                property real bloom: WallFx.bloom
                property real vhs: WallFx.vhs
                property real hue: WallFx.hue
                property real hueMix: WallFx.hueMix
                property real time: WallFx.time
                property size px: Qt.size(1 / width, 1 / height)
                property point center: Qt.point(MusicFx.x, MusicFx.y)
                property vector4d ages: WallFx.ages
                property vector4d amps: WallFx.amps
                property var glow: bloomTex
                property real sat: WallFx.sat
                property real contrast: WallFx.contrast
                fragmentShader: Qt.resolvedUrl("../../shaders/wallfx.frag.qsb")
            }

            // What bloom blurs: the content as it moves
            Item {
                id: scene
                anchors.fill: parent
            }
        }
    }

    // Quarter-size copy, blurred: the glow bloom screens over the content
    ShaderEffectSource {
        id: bloomSmall

        readonly property bool on: root.on && WallFx.on && MusicFx.bloom

        width: Math.max(1, Math.round(root.width / 4))
        height: Math.max(1, Math.round(root.height / 4))
        sourceItem: scene
        textureSize: Qt.size(width, height)
        live: on
        visible: false
    }

    MultiEffect {
        id: bloomBlur

        width: bloomSmall.width
        height: bloomSmall.height
        source: bloomSmall
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 32
    }

    ShaderEffectSource {
        id: bloomTex

        width: bloomSmall.width
        height: bloomSmall.height
        sourceItem: bloomBlur
        hideSource: true
        live: bloomSmall.on
        visible: false
    }
}
