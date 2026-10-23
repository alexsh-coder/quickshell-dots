pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Keeps the session awake while on; the inhibitor itself lives in the bar window
Singleton {
    id: root

    property bool enabled: false

    onEnabledChanged: if (saved.restored) saved.setText(enabled ? "on" : "off")

    // Survives a shell restart within the session, like night mode
    FileView {
        id: saved
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-caffeine"
        blockLoading: true
        printErrors: false

        property bool restored

        onLoaded: {
            if (!restored)
                root.enabled = text().trim() === "on";
            restored = true;
        }
        onLoadFailed: restored = true
    }

    function toggle(): void {
        enabled = !enabled;
    }

    IpcHandler {
        target: "caffeine"

        function toggle(): void {
            root.toggle();
        }
        function set(state: string): void {
            root.enabled = state === "on";
        }
        function get(): string {
            return root.enabled ? "on" : "off";
        }
    }
}
