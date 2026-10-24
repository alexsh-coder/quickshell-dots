import QtQuick
import QtQuick.Shapes
import qs.config
import qs.services

// Music glow over the wallpaper: from a screen edge or all of them, or radial around the visualizer's centre.
// Type, edge and size come from MusicFx; "halo" leaves only the visualizer's own shadow
Item {
    id: root

    property real strength: 0

    readonly property bool radial: MusicFx.glowType === "radial"
    // "around" glows from all four edges at once
    readonly property var sides: MusicFx.glowFrom === "around" ? ["top", "bottom", "left", "right"] : [MusicFx.glowFrom]
    readonly property real depth: MusicFx.glowFrom === "around" ? Math.min(width, height) * MusicFx.glowSize / 2 : -1
    readonly property color tint: Qt.alpha(Theme.fxColor, 0.35)

    visible: MusicFx.glowType !== "halo" && opacity > 0
    opacity: strength * MusicFx.fade

    Repeater {
        model: root.radial ? [] : root.sides

        Rectangle {
            required property string modelData
            readonly property bool horizontal: modelData === "left" || modelData === "right"
            // The glowing edge is at the gradient's start
            readonly property bool fromStart: modelData === "top" || modelData === "left"

            x: modelData === "right" ? root.width - width : 0
            y: modelData === "bottom" ? root.height - height : 0
            width: !horizontal ? root.width : root.depth >= 0 ? root.depth : root.width * MusicFx.glowSize
            height: horizontal ? root.height : root.depth >= 0 ? root.depth : root.height * MusicFx.glowSize
            gradient: Gradient {
                orientation: horizontal ? Gradient.Horizontal : Gradient.Vertical
                GradientStop { position: 0; color: fromStart ? root.tint : "transparent" }
                GradientStop { position: 1; color: fromStart ? "transparent" : root.tint }
            }
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
