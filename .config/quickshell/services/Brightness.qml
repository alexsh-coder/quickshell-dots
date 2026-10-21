pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property real value: 0
    property string pending: ""

    signal stepped

    function raise() { step("1%+"); }
    function lower() { step("1%-"); }
    // Absolute level, 0..1; shown right away, brightnessctl catches up
    function set(v) {
        value = v;
        step(Math.round(v * 100) + "%");
    }

    function step(delta) {
        if (proc.running) {
            pending = delta;
            return;
        }
        proc.command = ["brightnessctl", "-m", "-c", "backlight", "-e4", "-n2", "set", delta];
        proc.running = true;
    }

    // Held keys repeat faster than brightnessctl exits, so keep the latest step queued
    Process {
        id: proc
        command: ["brightnessctl", "-m", "-c", "backlight", "-e4", "info"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length < 4)
                    return;
                const first = !root.available;
                root.available = true;
                root.value = parseInt(f[3]) / 100;
                if (!first)
                    root.stepped();
            }
        }
        onExited: {
            if (root.pending) {
                const delta = root.pending;
                root.pending = "";
                root.step(delta);
            }
        }
    }
}
