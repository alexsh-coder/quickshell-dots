import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    property bool lit: false

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    Icon {
        id: icon
        anchors.centerIn: parent
        font.pixelSize: Theme.barIcon
        weight: 500
        fill: 0
        text: Vpn.on ? "vpn_key" : "vpn_key_off"
        color: parent.lit ? Theme.barAccent : Theme.secondary
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        SequentialAnimation on opacity {
            running: Vpn.busy
            loops: Animation.Infinite
            onRunningChanged: if (!running) icon.opacity = 1
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
