import QtQuick
import Quickshell
import qs.config
import qs.components

Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Label {
        text: Qt.formatDateTime(clock.date, "HH:mm")
        font.pixelSize: 16
        font.weight: Font.Bold
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "d MMM")
        color: Theme.subtext
    }
}
