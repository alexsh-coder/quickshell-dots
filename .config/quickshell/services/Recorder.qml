pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen recording state, reported by the record script over IPC
Singleton {
    id: root

    property bool active: false
    property real startedAt: 0
    property int elapsed: 0

    function stop(): void {
        Quickshell.execDetached(["pkill", "-INT", "-f", "^gpu-screen-recorder "]);
    }

    function begin(ago: int): void {
        startedAt = Date.now() - ago * 1000;
        elapsed = ago;
        active = true;
    }

    Timer {
        running: root.active
        interval: 1000
        repeat: true
        onTriggered: root.elapsed = Math.round((Date.now() - root.startedAt) / 1000)
    }

    // Picks up a recording that was already running when the shell started
    Process {
        running: true
        command: ["sh", "-c", "p=$(pgrep -f '^gpu-screen-recorder ' | head -n1) && ps -o etimes= -p \"$p\""]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim())
                root.begin(parseInt(text))
        }
    }

    IpcHandler {
        target: "recorder"

        function started(): void {
            root.begin(0);
        }
        function stopped(): void {
            root.active = false;
        }
    }
}
