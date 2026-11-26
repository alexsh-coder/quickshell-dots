import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Notifies once per threshold while discharging; charging re-arms them.
// At saverAt% switches to power-saver and restores the old profile on charge.
Scope {
    id: root

    readonly property var thresholds: [20, 10, 5]
    readonly property int saverAt: 20
    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property bool ready: (dev?.ready ?? false) && (dev?.isLaptopBattery ?? false)
    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)
    readonly property bool discharging: dev?.state === UPowerDeviceState.Discharging
                                     || dev?.state === UPowerDeviceState.PendingDischarge
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
                                  || dev?.state === UPowerDeviceState.FullyCharged

    PersistentProperties {
        id: saved
        reloadableId: "batteryAlert"
        property int warned: 101
        property int savedProfile: -1
    }

    function check() {
        if (!ready)
            return;
        if (charging) {
            saved.warned = 101;
            if (saved.savedProfile >= 0) {
                PowerProfiles.profile = saved.savedProfile;
                saved.savedProfile = -1;
            }
            return;
        }
        if (!discharging)
            return;
        if (pct <= saverAt && saved.savedProfile < 0
                && PowerProfiles.profile !== PowerProfile.PowerSaver) {
            saved.savedProfile = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        }
        const hit = thresholds.filter(t => pct <= t && t < saved.warned);
        if (!hit.length)
            return;
        const t = Math.min(...hit);
        saved.warned = t;
        notify.command = ["notify-send", "-a", "Battery", "-e",
            "-u", t <= 5 ? "critical" : "normal",
            "-i", t <= 10 ? "battery-caution" : "battery-low",
            "Low battery", `${pct}% remaining`];
        notify.running = true;
    }

    onPctChanged: check()
    onDischargingChanged: check()
    onChargingChanged: check()
    onReadyChanged: check()
    Component.onCompleted: check()

    Process { id: notify }
}
