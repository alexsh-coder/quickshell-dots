pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Music players by default; browsers, messengers etc. only when picked by hand
Singleton {
    readonly property var notMusic: ["firefox", "zen", "chromium", "chrome", "brave", "vivaldi", "opera", "edge", "librewolf", "telegram", "ayugram", "discord", "vesktop", "element", "signal"]
    readonly property var all: Mpris.players.values.filter(p => !p.dbusName.includes("playerctld"))
    readonly property var music: all.filter(p => !notMusic.some(b => (p.dbusName + " " + p.desktopEntry + " " + p.identity).toLowerCase().includes(b)))
    // every source with a track, music first; used for manual switching
    readonly property var withTrack: music.concat(all.filter(p => !music.includes(p))).filter(p => !!p.trackTitle)
    // shared source picked in any media popover
    property MprisPlayer chosen: null
    readonly property MprisPlayer current: (withTrack.includes(chosen) ? chosen : null) ?? music.find(p => p.isPlaying && !!p.trackTitle) ?? music.find(p => !!p.trackTitle) ?? music[0] ?? null
}
