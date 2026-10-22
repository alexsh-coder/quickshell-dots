import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    property bool lit: false

    readonly property var levels: ["signal_wifi_0_bar", "network_wifi_1_bar", "network_wifi_2_bar", "network_wifi_3_bar", "network_wifi"]

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
        text: Net.ethernet ? "cable"
            : !Net.wifiOn || !Net.active ? "wifi_off"
            : parent.levels[Math.max(0, Math.min(4, Math.floor(Net.active.signalStrength * 5)))]
        color: parent.lit ? Theme.barAccent : Theme.secondary
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }
}
