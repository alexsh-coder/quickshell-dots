import QtQuick
import qs.config
import qs.components

// Slider over from..to in steps, with its value written out
Item {
    id: root

    property real from: 0
    property real to: 1
    property real step: 0.1
    property real value
    property var format: v => String(v)
    signal moved(real v)

    implicitWidth: 260
    implicitHeight: 24

    Slider {
        anchors.left: parent.left
        anchors.right: text.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        value: (root.value - root.from) / (root.to - root.from)
        onMoved: v => {
            const x = Math.round((root.from + v * (root.to - root.from)) / root.step) * root.step;
            const snapped = Number(x.toFixed(4));
            if (snapped !== root.value)
                root.moved(snapped);
        }
    }

    Label {
        id: text
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 56
        horizontalAlignment: Text.AlignRight
        text: root.format(root.value)
        font.pixelSize: 12
        color: Theme.subtext
    }
}
