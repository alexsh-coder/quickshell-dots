import QtQuick
import Quickshell.Bluetooth
import qs.config
import qs.components

Item {
    id: root

    property bool lit: false
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter

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
        text: !root.adapter?.enabled ? "bluetooth_disabled"
            : Bluetooth.devices.values.some(d => d.connected) ? "bluetooth_connected"
            : "bluetooth"
        color: root.lit ? Theme.accent : Theme.secondary
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }
}
