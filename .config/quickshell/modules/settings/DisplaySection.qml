import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// Resolution, refresh rate, scale and VRR per monitor, applied and saved at once
Column {
    id: root

    property bool shown: false
    property var monitors: []

    readonly property var scales: [1, 1.2, 1.25, 1 + 1 / 3, 1.5, 1.6, 1 + 2 / 3, 2, 2.4, 2.5, 3]

    spacing: 6

    onShownChanged: if (shown) query.running = true

    Process {
        id: query
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    function rule(name, m) {
        return "hl.monitor({ output = \"" + name + "\", mode = \"" + m.mode + "\", position = \"auto\", scale = " + m.scale + ", vrr = " + m.vrr + " })";
    }

    function apply(name, next) {
        Quickshell.execDetached(["hyprctl", "eval", rule(name, next)]);
        Settings.setMonitor(name, next);
        refresh.restart();
    }

    // The monitor takes a moment to switch modes
    Timer {
        id: refresh
        interval: 800
        onTriggered: query.running = true
    }

    Repeater {
        model: root.monitors

        Column {
            id: mon

            required property var modelData
            readonly property string name: modelData.name
            readonly property var modes: (modelData.availableModes ?? []).map(s => {
                const m = s.replace(/Hz$/, "").split("@");
                return { res: m[0], rate: m[1] };
            })
            readonly property string curRes: modelData.width + "x" + modelData.height
            readonly property string curRate: (modelData.refreshRate ?? 60).toFixed(2)
            readonly property real curScale: modelData.scale ?? 1
            readonly property int curVrr: modelData.vrr ? 1 : 0

            property string res: curRes
            property string rate: curRate
            property real factor: curScale
            property int vrr: curVrr

            readonly property var resolutions: modes.map(m => m.res).filter((r, i, a) => a.indexOf(r) === i)
            readonly property var rates: modes.filter(m => m.res === res).map(m => m.rate).filter((r, i, a) => a.indexOf(r) === i)
            readonly property var size: res.split("x").map(Number)
            // Hyprland wants a scale that leaves whole logical pixels
            readonly property var scales: root.scales.filter(s => {
                const w = size[0] / s, h = size[1] / s;
                return Math.abs(w - Math.round(w)) < 0.01 && Math.abs(h - Math.round(h)) < 0.01;
            })
            readonly property bool changed: res !== curRes || rate !== curRate || Math.abs(factor - curScale) > 0.001 || vrr !== curVrr

            // Follows the monitor after a change or a rollback
            onCurResChanged: res = curRes
            onCurRateChanged: rate = curRate
            onCurScaleChanged: factor = curScale
            onCurVrrChanged: vrr = curVrr

            width: root.width
            spacing: 6

            SectionTitle {
                text: mon.name + (mon.modelData.model ? " · " + mon.modelData.model : "")
            }

            Label {
                text: "Resolution"
                font.pixelSize: 14
                topPadding: 6
            }
            Chips {
                maxWidth: mon.width
                current: mon.res
                model: mon.resolutions.map(r => ({ value: r, label: r.replace("x", "×") }))
                onPicked: v => {
                    mon.res = v;
                    if (!mon.rates.includes(mon.rate))
                        mon.rate = mon.rates[0];
                    if (!mon.factors.some(s => Math.abs(s - mon.factor) < 0.001))
                        mon.factor = 1;
                }
            }

            Label {
                text: "Refresh rate"
                font.pixelSize: 14
                topPadding: 8
            }
            Chips {
                maxWidth: mon.width
                current: mon.rate
                model: mon.rates.map(r => ({ value: r, label: Math.round(Number(r) * 100) / 100 + " Hz" }))
                onPicked: v => mon.rate = v
            }

            Label {
                text: "Scale"
                font.pixelSize: 14
                topPadding: 8
            }
            Chips {
                maxWidth: mon.width
                current: mon.factors.find(s => Math.abs(s - mon.factor) < 0.001)
                model: mon.factors.map(s => ({ value: s, label: Math.round(s * 100) + "%" }))
                onPicked: v => mon.factor = v
            }
            Label {
                text: "Looks like " + Math.round(mon.size[0] / mon.factor) + "×" + Math.round(mon.size[1] / mon.factor)
                font.pixelSize: 12
                color: Theme.subtext
            }

            SettingRow {
                label: "Variable refresh rate"
                hint: "Lets games set the pace when the screen supports it"

                Toggle {
                    checked: mon.vrr === 1
                    onToggled: mon.vrr = mon.vrr ? 0 : 1
                }
            }

            Row {
                spacing: 8

                PillButton {
                    text: "Apply"
                    icon: "check"
                    primary: true
                    enabled: mon.changed
                    onClicked: root.apply(mon.name, { mode: mon.res + "@" + mon.rate, scale: mon.factor, vrr: mon.vrr })
                }
                PillButton {
                    text: "Reset"
                    visible: mon.changed
                    onClicked: {
                        mon.res = mon.curRes;
                        mon.rate = mon.curRate;
                        mon.factor = mon.curScale;
                        mon.vrr = mon.curVrr;
                    }
                }
            }
        }
    }

    SectionTitle { text: "Night light" }

    SettingRow {
        label: "Warmth"
        hint: "Colour temperature while night light is on (Super+Shift+N)"

        ValueSlider {
            from: 2500
            to: 6000
            step: 100
            value: Settings.nightTemp
            format: v => v + " K"
            onMoved: v => Settings.nightTemp = v
        }
    }
}
