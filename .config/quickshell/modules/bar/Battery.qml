import QtQuick
import Quickshell.Services.UPower
import qs.config
import qs.components

Row {
    id: root

    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
                                  || dev?.state === UPowerDeviceState.FullyCharged
    readonly property bool low: !charging && pct <= 15
    property bool lit: false

    visible: dev?.isLaptopBattery ?? false
    anchors.verticalCenter: parent.verticalCenter
    spacing: 7

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    readonly property string icon: {
        const p = dev?.percentage ?? 0;
        if (p >= 1)
            return charging ? "battery_charging_full" : "battery_full";
        let level = Math.floor(p * 7);
        // Material has no charging_40 or charging_70
        if (charging && (level === 4 || level === 1))
            level--;
        return charging ? `battery_charging_${(level + 3) * 10}` : `battery_${level}_bar`;
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: Theme.barIcon
        weight: 500
        text: root.icon
        color: root.low ? Theme.urgent : root.lit ? Theme.barAccent : Theme.secondary
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }
}
