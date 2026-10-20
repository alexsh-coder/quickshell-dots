pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: (Quickshell.env("XDG_PICTURES_DIR") || home + "/Pictures") + "/Wallpapers"
    property string current: ""

    function refresh() {
        query.running = true;
    }

    function set(path) {
        current = path;
        // Grows out of the bottom edge, where the picker sits
        Quickshell.execDetached([
            "awww", "img", path,
            "--transition-type", "grow",
            "--transition-pos", "bottom",
            "--transition-duration", "0.8",
            "--transition-fps", "60"
        ]);
    }

    Process {
        id: query
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/image: (.+)$/m);
                root.current = m ? m[1].trim().replace(/^~/, root.home) : "";
            }
        }
    }

    Component.onCompleted: refresh()
}
