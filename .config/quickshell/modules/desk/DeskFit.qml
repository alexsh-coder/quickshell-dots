import QtQuick
import QtQuick.Effects
import qs.config

// Lays a widget's content out at its natural size and scales it to fit the widget's rect, keeping
// its proportions. Optionally on a card; without one, a soft halo keeps text readable on the wallpaper
Item {
    id: root

    default property alias content: inner.data
    property string align: "center"
    property bool card: false
    // The content's main color: the halo goes the other way
    property color tint: Theme.text
    readonly property real pad: card ? 32 : 0
    // The content is the one visual child; its implicit size is its natural size
    readonly property Item body: inner.children.length ? inner.children[0] : null
    readonly property real fit: Math.max(0.01, Math.min(width / Math.max(1, box.width), height / Math.max(1, box.height)))

    // The halo is drawn from a copy under the content, so the content itself stays crisp vector text
    MultiEffect {
        visible: !root.card
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        scale: box.scale
        transformOrigin: Item.TopLeft
        source: copy
        shadowEnabled: true
        shadowColor: root.tint.hslLightness > 0.5 ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.55)
        shadowBlur: 0.8
        shadowScale: 1.02
    }

    // A real item in the tree: an inline source object crashed Qt when the widget was destroyed
    ShaderEffectSource {
        id: copy
        visible: false
        sourceItem: root.card ? null : box
        hideSource: false
        live: !root.card
        smooth: true
        textureSize: Qt.size(Math.ceil(box.width * box.scale), Math.ceil(box.height * box.scale))
    }

    Item {
        id: box

        width: (root.body?.implicitWidth ?? 0) + 2 * root.pad
        height: (root.body?.implicitHeight ?? 0) + 2 * root.pad
        scale: root.fit
        transformOrigin: Item.TopLeft
        x: root.align === "left" ? 0 : root.align === "right" ? root.width - width * scale : (root.width - width * scale) / 2
        y: (root.height - height * scale) / 2

        Rectangle {
            anchors.fill: parent
            visible: root.card
            radius: 40
            color: Qt.alpha(Theme.bg, 0.6)
            border.width: 2
            border.color: Qt.alpha(Theme.text, 0.08)
        }

        Item {
            id: inner
            x: root.pad
            y: root.pad
            width: root.body?.implicitWidth ?? 0
            height: root.body?.implicitHeight ?? 0
        }
    }
}
