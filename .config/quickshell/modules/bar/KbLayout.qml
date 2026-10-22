import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    property bool lit: false

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    Label {
        id: label
        anchors.centerIn: parent
        text: (Keyboard.layout || "--").toLowerCase()
        font.pixelSize: 14
        font.weight: Font.Bold
        color: parent.lit ? Theme.barAccent : Theme.secondary
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }
}
