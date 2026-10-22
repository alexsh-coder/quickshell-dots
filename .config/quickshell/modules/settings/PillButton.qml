import QtQuick
import qs.config
import qs.components

Rectangle {
    id: root

    property string text
    property string icon: ""
    // Filled with the accent, for the main action
    property bool primary: false
    signal clicked

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 34
    radius: height / 2
    opacity: enabled ? 1 : 0.45
    color: primary ? (area.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
        : area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Icon {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.pixelSize: 18
            color: root.primary ? Theme.bg : Theme.text
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: root.primary ? Theme.bg : Theme.text
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
