import QtQuick
import qs.config
import qs.components
import qs.services

Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: label.implicitWidth + 16
    implicitHeight: 24
    radius: 6
    color: Theme.surface

    Label {
        id: label
        anchors.centerIn: parent
        text: Keyboard.layout || "--"
        font.pixelSize: 13
        font.weight: Font.Bold
        color: Theme.accent
    }
}
