pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night light state, mirroring the hyprsunset toggle script
Singleton {
    id: root

    property bool enabled: false

    readonly property string script: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                     + "/hypr/scripts/night-mode-toggle.sh"

    function apply(on: bool): void {
        const ok = Quickshell.execDetached([script, on ? "on" : "off"]);
        if (!ok)
            console.warn("night mode: failed to start", script);
        enabled = ok ? on : enabled;
    }

    function toggle(): void {
        apply(!enabled);
    }

    IpcHandler {
        target: "night"

        function toggle(): void {
            root.toggle();
        }
        function set(state: string): void {
            root.apply(state === "on");
        }
        function get(): string {
            return root.enabled ? "on" : "off";
        }
    }

    // The script owns the real state; watching its file keeps the bar honest,
    // including toggles made from a terminal
    FileView {
        id: state
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hyprsunset-night-light"
        watchChanges: true
        blockLoading: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: root.enabled = text().trim() === "on"
    }
}
