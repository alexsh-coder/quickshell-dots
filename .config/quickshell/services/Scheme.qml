pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Light/dark color scheme, persisted between sessions
Singleton {
    id: root

    property bool light: false
    // 0 = light, 1 = dark; animated, so colors cross-fade instead of snapping
    property real dark: light ? 0 : 1
    property bool ready: false

    Behavior on dark {
        enabled: root.ready
        NumberAnimation {
            duration: 500
            easing.type: Easing.InOutSine
        }
    }

    // Blends a light-scheme value into its dark-scheme counterpart
    function pick(lightColor, darkColor) {
        return Qt.tint(lightColor, Qt.alpha(darkColor, dark));
    }

    onLightChanged: saved.setText(light ? "light" : "dark")

    FileView {
        id: saved
        path: Quickshell.statePath("scheme")
        blockLoading: true
        printErrors: false
    }

    IpcHandler {
        target: "theme"

        function toggle(): void {
            root.light = !root.light;
        }
        function set(name: string): void {
            if (name === "light" || name === "dark")
                root.light = name === "light";
        }
        function get(): string {
            return root.light ? "light" : "dark";
        }
    }

    Component.onCompleted: {
        light = saved.text().trim() === "light";
        ready = true;
    }
}
