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
    // Or where the cursor is, in item pixels: then it spreads out from there, and what slides in
    // comes from the nearest edge
    property point cursor: Qt.point(-1e6, -1e6)
    readonly property bool fromCursor: cursor.x > -1e5
    readonly property string edge: !fromCursor ? origin : nearest()
    readonly property real radial: fromCursor ? 1 : 0
    readonly property point point: fromCursor ? Qt.point(cursor.x / Math.max(1, width), cursor.y / Math.max(1, height)) : Qt.point(0.5, 0.5)
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
    })[edge] ?? Qt.vector4d(0, -1, 1, 0)
    readonly property bool side: origin === "left" || origin === "right"
    readonly property point center: fromCursor ? cursor : side ? Qt.point(origin === "left" ? 0 : width, height / 2)
        : Qt.point(width / 2, origin === "top" ? 0 : height)
    // Circle and ripple: eased, out to the farthest corner (and the ripple's wave past it)
    readonly property real far: Math.max(Math.hypot(center.x, center.y), Math.hypot(width - center.x, center.y),
        Math.hypot(center.x, height - center.y), Math.hypot(width - center.x, height - center.y))
    readonly property real radius: -(Math.cos(Math.PI * t) - 1) / 2 * (far + (effect === 11 ? 0.08 * Math.hypot(width, height) : 0))
    readonly property color glow: Theme.accent

    fragmentShader: Qt.resolvedUrl("../../shaders/wallswap.frag.qsb")

    function nearest() {
        const d = { left: cursor.x, right: width - cursor.x, top: cursor.y, bottom: height - cursor.y };
        return Object.keys(d).reduce((a, b) => d[a] <= d[b] ? a : b);
    }

    // Crop of an Image filling its item with PreserveAspectCrop: the shader gets the whole texture
    function cropOf(img) {
        return Qt.size(Math.min(1, img.width / Math.max(1, img.paintedWidth)), Math.min(1, img.height / Math.max(1, img.paintedHeight)));
    }
}
