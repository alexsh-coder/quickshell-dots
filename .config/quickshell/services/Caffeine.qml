pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Keeps the session awake while on; the inhibitor itself lives in the bar window
Singleton {
    id: root

    property bool enabled: false

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
