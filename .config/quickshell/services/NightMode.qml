pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night light through hyprsunset's IPC; Hyprland keeps the daemon running
Singleton {
    id: root

    property bool enabled: false
    readonly property int temperature: Settings.nightTemp

    // A new warmth from the settings window shows right away
    onTemperatureChanged: if (enabled) apply(true)

    // A change made by the user, for the OSD
    signal switched

    function apply(on: bool): void {
        enabled = on;
        if (proc.running) {
            proc.queued = true;
            return;
        }
        // identity is a true bypass; 6500K still leaves a slight tint
        proc.target = on;
        proc.command = on ? ["hyprctl", "hyprsunset", "temperature", String(temperature)]
                          : ["hyprctl", "hyprsunset", "identity"];
        proc.running = true;
    }

    function toggle(): void {
        apply(!enabled);
        switched();
    }

    Process {
        id: proc

        property bool target
        property bool queued

        onExited: code => {
            if (code !== 0) {
                console.warn("night mode: hyprsunset is not running");
                root.enabled = false;
                queued = false;
                return;
            }
            saved.setText(target ? "on" : "off");
            if (queued) {
                queued = false;
                if (target !== root.enabled)
                    root.apply(root.enabled);
            }
        }
    }

    // Survives a shell restart within the session; hyprsunset starts untinted at login
    FileView {
        id: saved
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-night-mode"
        blockLoading: true
        printErrors: false

        property bool restored

        onLoaded: {
            if (!restored && text().trim() === "on")
                root.apply(true);
            restored = true;
        }
    }

    IpcHandler {
        target: "night"

        function toggle(): void {
            root.toggle();
        }
        function set(state: string): void {
            if ((state === "on") !== root.enabled)
                root.toggle();
        }
        function get(): string {
            return root.enabled ? "on" : "off";
        }
    }
}
