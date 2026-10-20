import QtQuick
import qs.config
import qs.services

// Mirrored spectrum bars that read like a waveform; folds away when nothing plays
Item {
    id: root

    readonly property int barWidth: 3
    readonly property int gap: 2
    readonly property int fullWidth: Cava.bars * barWidth + (Cava.bars - 1) * gap

    implicitWidth: Cava.active ? fullWidth : 0
    implicitHeight: 24
    anchors.verticalCenter: parent.verticalCenter
    opacity: Cava.active ? 1 : 0
    visible: implicitWidth > 0
    clip: true

    Behavior on implicitWidth { NumberAnimation { duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap

        Repeater {
            model: Cava.bars

            Rectangle {
                required property int index

                anchors.verticalCenter: parent.verticalCenter
                width: root.barWidth
                height: Math.max(root.barWidth, Cava.values[index] * root.implicitHeight)
                radius: root.barWidth / 2
                color: Theme.accent

                Behavior on height { NumberAnimation { duration: 50 } }
            }
        }
    }
}
