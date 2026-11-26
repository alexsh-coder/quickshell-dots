pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS players minus browsers (YouTube etc.)
Singleton {
    readonly property var browsers: ["firefox", "zen", "chromium", "chrome", "brave", "vivaldi", "opera", "edge", "librewolf"]
    readonly property var music: Mpris.players.values.filter(p => !browsers.some(b => (p.dbusName + " " + p.desktopEntry + " " + p.identity).toLowerCase().includes(b)))
}
