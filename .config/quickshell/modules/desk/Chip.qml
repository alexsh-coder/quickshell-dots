import QtQuick
import qs.config
import qs.components

// Small pill button: filled when on, outlined otherwise
Rectangle {
    id: root

    property string text
    property string icon
    property bool on: false
    signal clicked

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 28
    radius: height / 2
    color: on ? Theme.accent : area.containsMouse ? Theme.muted : "transparent"
    border.width: 1
    border.color: on ? Theme.accent : Theme.muted
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 5

        Icon {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.pixelSize: 16
            fill: root.on ? 1 : 0
            color: root.on ? Theme.bg : Theme.text
        }

        Label {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: 12
            color: root.on ? Theme.bg : Theme.subtext
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
