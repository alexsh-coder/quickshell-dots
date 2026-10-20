pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property string layout: ""
    property bool caps: false
    property bool capsRequested: false

    signal layoutSwitched
    signal capsToggled

    property bool capsBefore: false
    property int capsTries: 0

    // Bound on key press, but xkb unlocks Caps only on release, so poll until the state flips
    function checkCaps() {
        if (!capsRequested)
            capsBefore = caps;
        capsRequested = true;
        capsTries = 0;
        capsPoll.restart();
    }

    Timer {
        id: capsPoll
        interval: 50
        onTriggered: query.running = true
    }

    // activelayout fires for every keyboard (incl. virtual ones), so ask Hyprland for the main one
    Process {
        id: query
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const kbs = JSON.parse(text).keyboards;
                const kb = kbs.find(k => k.main) ?? kbs[0];
                if (!kb)
                    return;
                const name = kb.active_keymap.slice(0, 2).toUpperCase();
                const first = root.layout === "";
                root.caps = kb.capsLock;
                if (name !== root.layout) {
                    root.layout = name;
                    if (!first)
                        root.layoutSwitched();
                }
                if (root.capsRequested) {
                    if (root.caps === root.capsBefore && ++root.capsTries < 30) {
                        capsPoll.restart();
                        return;
                    }
                    root.capsRequested = false;
                    root.capsToggled();
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout")
                query.running = true;
        }
    }
}
