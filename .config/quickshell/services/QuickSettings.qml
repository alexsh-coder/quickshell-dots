pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Whether the quick settings card is up; the OSD keeps quiet meanwhile
Singleton {
    id: root

    property bool open: false

    function toggle(): void {
        open = !open;
    }

    IpcHandler {
        target: "quicksettings"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open = true;
        }
        function close(): void {
            root.open = false;
        }
    }
}
