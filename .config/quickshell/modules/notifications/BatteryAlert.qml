import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Notifies once per threshold while discharging; plugging in re-arms them
Scope {
    id: root

    readonly property var thresholds: [30, 15, 5]
    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property bool ready: (dev?.ready ?? false) && (dev?.isLaptopBattery ?? false)
    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)
    readonly property bool discharging: dev?.state === UPowerDeviceState.Discharging
                                     || dev?.state === UPowerDeviceState.PendingDischarge

    PersistentProperties {
        id: saved
        reloadableId: "batteryAlert"
        property int warned: 101
    }

    function check() {
        if (!ready)
            return;
        if (!discharging) {
            saved.warned = 101;
            return;
        }
        const hit = thresholds.filter(t => pct <= t && t < saved.warned);
        if (!hit.length)
            return;
        const t = Math.min(...hit);
        saved.warned = t;
        notify.command = ["notify-send", "-a", "Battery",
            "-u", t <= 5 ? "critical" : "normal",
            "-i", t <= 15 ? "battery-caution" : "battery-low",
            "Low battery", `${pct}% remaining`];
        notify.running = true;
    }

    onPctChanged: check()
    onDischargingChanged: check()
    onReadyChanged: check()
    Component.onCompleted: check()

    Process { id: notify }
}
