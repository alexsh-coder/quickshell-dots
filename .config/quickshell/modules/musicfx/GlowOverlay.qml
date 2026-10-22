import QtQuick
import QtQuick.Shapes
import qs.config
import qs.services

// Music glow over the wallpaper: from a screen edge, or radial around the visualizer's centre.
// Type, edge and size come from MusicFx; "halo" leaves only the visualizer's own shadow
Item {
    id: root

    property real strength: 0

    readonly property bool radial: MusicFx.glowType === "radial"
    readonly property bool horizontal: MusicFx.glowFrom === "left" || MusicFx.glowFrom === "right"
    // The glowing edge is at the gradient's start
    readonly property bool fromStart: MusicFx.glowFrom === "top" || MusicFx.glowFrom === "left"
    readonly property color tint: Qt.alpha(Theme.fxColor, 0.35)

    visible: MusicFx.glowType !== "halo" && opacity > 0
    opacity: strength * MusicFx.fade

    Rectangle {
        visible: !root.radial
        x: MusicFx.glowFrom === "right" ? parent.width - width : 0
        y: MusicFx.glowFrom === "bottom" ? parent.height - height : 0
        width: root.horizontal ? parent.width * MusicFx.glowSize : parent.width
        height: root.horizontal ? parent.height : parent.height * MusicFx.glowSize
        gradient: Gradient {
            orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0; color: root.fromStart ? root.tint : "transparent" }
            GradientStop { position: 1; color: root.fromStart ? "transparent" : root.tint }
        }
    }

    Shape {
        visible: root.radial
        anchors.fill: parent

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: MusicFx.x * root.width
                centerY: MusicFx.y * root.height
                centerRadius: root.height * MusicFx.glowSize
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0; color: root.tint }
                GradientStop { position: 1; color: "transparent" }
            }
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.width, 0), Qt.point(root.width, root.height), Qt.point(0, root.height), Qt.point(0, 0)]
            }
        }
    }
}
