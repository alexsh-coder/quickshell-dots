import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// Resolution, refresh rate, scale and VRR per monitor. A change is tried first and rolls back
// unless kept within a few seconds, so a mode the screen can't show undoes itself
Column {
    id: root

    property bool shown: false
    property var monitors: []
    // { name, old, next } while waiting to be kept
    property var trial: null
    property int countdown: 0

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

    function tryOut(name, old, next) {
        trial = { name: name, old: old, next: next };
        countdown = 15;
        Quickshell.execDetached(["hyprctl", "eval", rule(name, next)]);
        refresh.restart();
    }

    function keep() {
        Settings.setMonitor(trial.name, trial.next);
        trial = null;
    }

    function revert() {
        Quickshell.execDetached(["hyprctl", "eval", rule(trial.name, trial.old)]);
        trial = null;
        refresh.restart();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.trial !== null
        onTriggered: {
            if (--root.countdown <= 0)
                root.revert();
        }
    }

    // The monitor takes a moment to switch modes
    Timer {
        id: refresh
        interval: 800
        onTriggered: query.running = true
    }

    // Keep or roll back
    Rectangle {
        width: parent.width
        height: root.trial ? 64 : 0
        visible: height > 0
        radius: Theme.radius
        color: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.14))
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Label {
                text: "Keep these display settings?"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Label {
                text: "Going back in " + root.countdown + " s"
                font.pixelSize: 12
                color: Theme.subtext
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            PillButton {
                text: "Revert"
                onClicked: root.revert()
            }
            PillButton {
                text: "Keep"
                primary: true
                onClicked: root.keep()
            }
        }
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
                    enabled: mon.changed && !root.trial
                    onClicked: root.tryOut(mon.name,
                        { mode: mon.curRes + "@" + mon.curRate, scale: mon.curScale, vrr: mon.curVrr },
                        { mode: mon.res + "@" + mon.rate, scale: mon.factor, vrr: mon.vrr })
                }
                PillButton {
                    text: "Reset"
                    visible: mon.changed && !root.trial
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
