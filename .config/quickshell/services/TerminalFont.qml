pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// kitty's font size, kept in the per-machine kitty/machine.conf and pushed to running kittys
Singleton {
    id: root

    readonly property real fallback: 13
    property real size: fallback

    function set(v) {
        size = v;
        debounce.restart();
    }

    function parse(text) {
        const m = text.match(/^\s*font_size\s+([\d.]+)/m);
        return m ? Number(m[1]) : fallback;
    }

    function apply() {
        const old = conf.text() || "";
        const line = "font_size " + size.toFixed(1);
        const text = /^\s*font_size\s.*$/m.test(old) ? old.replace(/^\s*font_size\s.*$/m, line) : old + (old && !old.endsWith("\n") ? "\n" : "") + line + "\n";
        conf.setText(text);
        // kitty suffixes its listen_on socket with -<pid>, one per instance
        Quickshell.execDetached(["sh", "-c", 'for p in $(pgrep -x kitty); do kitty @ --to "unix:@kitty-$p" set-font-size "$1"; done', "sh", String(size)]);
    }

    Timer {
        id: debounce
        interval: 250
        onTriggered: root.apply()
    }

    FileView {
        id: conf
        path: Quickshell.env("HOME") + "/.config/kitty/machine.conf"
        printErrors: false
        onLoaded: root.size = root.parse(text())
    }
}
