import QtQuick
import Quickshell
import qs.config
import qs.components

Rectangle {
    id: root

    property bool lit: false

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: row.implicitWidth + 28
    implicitHeight: 30
    radius: height / 2
    color: Theme.surface

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    // State layer, tinted by the content colour
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.tertiary
        opacity: root.lit ? 0.16 : hover.hovered ? 0.1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 18
            weight: 500
            fill: 0
            text: "calendar_month"
            color: Theme.tertiary
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: 16
            font.weight: Font.Bold
            color: Theme.tertiary
        }
    }
}
