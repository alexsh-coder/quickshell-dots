import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// Binds hyprland.lua makes through bind(id, "Group|Label", ...), read back from hyprctl
Column {
    id: root

    property bool shown: false
    property var all: []
    property var groups: []
    // id being recorded, "" when none
    property string recording: ""
    property string error: ""

    spacing: 6

    readonly property var modBits: [[64, "SUPER"], [1, "SHIFT"], [4, "CTRL"], [8, "ALT"]]
    // xkb keycodes (evdev + 8) to the US keysyms Hyprland matches, so any layout records the same
    readonly property var keyNames: (() => {
        const m = {};
        const row = (from, keys) => keys.split(" ").forEach((k, i) => m[from + i + 8] = k);
        row(1, "Escape 1 2 3 4 5 6 7 8 9 0 minus equal BackSpace TAB Q W E R T Y U I O P bracketleft bracketright Return");
        row(30, "A S D F G H J K L semicolon apostrophe grave");
        row(43, "backslash Z X C V B N M comma period slash");
        row(57, "SPACE");
        row(59, "F1 F2 F3 F4 F5 F6 F7 F8 F9 F10");
        row(87, "F11 F12");
        row(99, "Print");
        row(102, "Home up Prior left right End down Next Insert Delete");
        return m;
    })()

    function combo(mods, key) {
        return modBits.filter(b => mods & b[0]).map(b => b[1]).concat([key]).join(" + ");
    }
    function norm(c) {
        return c.toLowerCase().replace(/\s+/g, "");
    }
    function pretty(c) {
        return c.split(" + ").map(p => p.length > 1 ? p[0].toUpperCase() + p.slice(1).toLowerCase() : p).join(" + ");
    }

    function refresh() {
        proc.running = true;
    }

    function setSubmap(name) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"" + name + "\")"]);
    }

    function start(id) {
        error = "";
        recording = id;
        setSubmap("rebind");
        catcher.forceActiveFocus();
    }

    function stop() {
        if (!recording)
            return;
        recording = "";
        setSubmap("");
    }

    function record(event) {
        const name = keyNames[event.nativeScanCode];
        if (event.key === Qt.Key_Escape && !event.modifiers)
            return stop();
        if (!name)
            return;
        let mods = 0;
        if (event.modifiers & Qt.MetaModifier) mods |= 64;
        if (event.modifiers & Qt.ShiftModifier) mods |= 1;
        if (event.modifiers & Qt.ControlModifier) mods |= 4;
        if (event.modifiers & Qt.AltModifier) mods |= 8;
        if (!mods && !/^(F\d+|Print)$/.test(name)) {
            error = "Add a modifier: Super, Ctrl, Alt or Shift";
            return;
        }
        const keys = combo(mods, name);
        const taken = all.find(b => b.id !== recording && norm(b.keys) === norm(keys));
        if (taken) {
            error = pretty(keys) + " is already " + (taken.label || "taken by Hyprland");
            return;
        }
        const id = recording;
        stop();
        Settings.setBind(id, keys);
        later.restart();
    }

    onShownChanged: shown ? refresh() : stop()
    Component.onDestruction: stop()

    Process {
        id: proc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = JSON.parse(text).filter(b => !b.submap).map(b => {
                    const d = b.has_description ? b.description.split("|") : [];
                    return { id: d.length === 3 ? d[0] : "", group: d[1] ?? "", label: d[2] ?? "", keys: root.combo(b.modmask, b.key) };
                });
                root.all = list;
                const order = [];
                for (const b of list.filter(b => b.id))
                    (order.find(g => g.name === b.group) ?? order[order.push({ name: b.group, binds: [] }) - 1]).binds.push(b);
                root.groups = order;
            }
        }
    }

    // settings.lua is written and Hyprland reloaded after a short debounce
    Timer {
        id: later
        interval: 900
        onTriggered: root.refresh()
    }

    Item {
        id: catcher
        Keys.onPressed: event => {
            event.accepted = true;
            root.record(event);
        }
        onActiveFocusChanged: if (!activeFocus) root.stop()
    }

    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.error || "Click a shortcut and press the new keys · Esc cancels"
        color: root.error ? Theme.urgent : Theme.subtext
        font.pixelSize: 12
    }

    Repeater {
        model: root.groups

        Column {
            required property var modelData
            width: root.width
            spacing: 6

            SectionTitle { text: modelData.name }

            Repeater {
                model: modelData.binds

                SettingRow {
                    id: row
                    required property var modelData
                    readonly property bool custom: Settings.binds[modelData.id] !== undefined
                    readonly property bool active: root.recording === modelData.id

                    label: modelData.label

                    Row {
                        spacing: 6

                        Icon {
                            visible: row.custom
                            anchors.verticalCenter: parent.verticalCenter
                            text: "restart_alt"
                            font.pixelSize: 20
                            color: resetArea.containsMouse ? Theme.accent : Theme.subtext
                            MouseArea {
                                id: resetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Settings.setBind(row.modelData.id, "");
                                    later.restart();
                                }
                            }
                        }

                        PillButton {
                            text: row.active ? "Press keys…" : root.pretty(row.modelData.keys)
                            primary: row.active
                            onClicked: row.active ? root.stop() : root.start(row.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
