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

    visible: dev?.isLaptopBattery ?? false
    anchors.verticalCenter: parent.verticalCenter
    spacing: 7

    // nf-md battery glyphs, 0..100% in steps of 10
    readonly property var levels: ["\u{f008e}", "\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}",
                                   "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"]
    readonly property var chargingLevels: ["\u{f089f}", "\u{f089c}", "\u{f0086}", "\u{f0087}", "\u{f0088}", "\u{f089d}",
                                           "\u{f0089}", "\u{f089e}", "\u{f008a}", "\u{f008b}", "\u{f0085}"]

    NerdIcon {
        anchors.verticalCenter: parent.verticalCenter
        text: (root.charging ? root.chargingLevels : root.levels)[Math.round(root.pct / 10)]
        color: root.low ? Theme.urgent : root.charging ? Theme.accent : Theme.text
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: root.pct + "%"
        color: root.low ? Theme.urgent : Theme.text
    }
}
