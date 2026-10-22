import QtQuick
import qs.config

// One wallpaper transition at progress t (shaders/wallswap.frag): source comes in over what lies
// under it, previous is the wallpaper it replaces when there's a still of it
ShaderEffect {
    id: root

    property Item source
    property Item previous
    property bool hasPrevious: false
    property real t: 0
    property int effect: 0
    // Edge it comes from: bottom, left, right or top
    property string origin: "bottom"
    // Share of each texture shown, for images drawn cropped (PreserveAspectCrop)
    property size cropTo: Qt.size(1, 1)
    property size cropFrom: Qt.size(1, 1)

    readonly property real mode: effect
    readonly property real hasFrom: hasPrevious && previous ? 1 : 0
    readonly property size extent: Qt.size(width, height)
    readonly property vector4d axis: ({
        right: Qt.vector4d(-1, 0, 1, 0),
        left: Qt.vector4d(1, 0, 0, 0),
        top: Qt.vector4d(0, 1, 0, 0)
    })[origin] ?? Qt.vector4d(0, -1, 1, 0)
    readonly property bool side: origin === "left" || origin === "right"
    readonly property point center: side ? Qt.point(origin === "left" ? 0 : width, height / 2)
        : Qt.point(width / 2, origin === "top" ? 0 : height)
    // Circle and ripple: eased, out to the farthest corner (and the ripple's wave past it)
    readonly property real radius: -(Math.cos(Math.PI * t) - 1) / 2
        * ((side ? Math.hypot(width, height / 2) : Math.hypot(width / 2, height)) + (effect === 11 ? 0.08 * Math.hypot(width, height) : 0))
    readonly property color glow: Theme.accent

    fragmentShader: Qt.resolvedUrl("../../shaders/wallswap.frag.qsb")

    // Crop of an Image filling its item with PreserveAspectCrop: the shader gets the whole texture
    function cropOf(img) {
        return Qt.size(Math.min(1, img.width / Math.max(1, img.paintedWidth)), Math.min(1, img.height / Math.max(1, img.paintedHeight)));
    }
}
