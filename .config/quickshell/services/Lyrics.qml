pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Time-synced lyrics for the active MPRIS player, word-synced where available
// (see scripts/lyrics.py)
Singleton {
    id: root

    readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property string key: player ? [player.trackArtist, player.trackTitle].join("\n") : ""

    property var lines: []
    property int index: -1
    property var cache: ({})

    onKeyChanged: load()
    Component.onCompleted: load()

    function load() {
        lines = cache[key] ?? [];
        index = -1;
        if (key.trim() && !(key in cache))
            debounce.restart();
    }

    // Drops all cached lyrics: a hand-made file also covers other versions of the track
    function reload() {
        cache = {};
        load();
    }

    function update() {
        if (!player || !lines.length)
            return;
        const pos = player.position;
        let i = index >= 0 && lines[index].time <= pos ? index : 0;
        while (i + 1 < lines.length && lines[i + 1].time <= pos)
            i++;
        index = i;
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: {
            const p = root.player;
            if (!p)
                return;
            fetch.reqKey = root.key;
            fetch.exec(["python3", Quickshell.shellDir + "/scripts/lyrics.py",
                p.trackArtist, p.trackTitle, p.trackAlbum, String(p.length)]);
        }
    }

    Process {
        id: fetch
        property string reqKey
        stdout: StdioCollector {
            onStreamFinished: {
                let lines;
                try {
                    lines = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const c = Object.assign({}, root.cache);
                c[fetch.reqKey] = lines;
                root.cache = c;
                if (fetch.reqKey === root.key) {
                    root.lines = lines;
                    root.update();
                }
            }
        }
    }

    // MprisPlayer.position is computed on read, so poll it while playing
    Timer {
        interval: 100
        repeat: true
        running: (root.player?.isPlaying ?? false) && root.lines.length > 0
        onTriggered: root.update()
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.update(); }
    }

    IpcHandler {
        target: "lyrics"

        function toggle(): void {
            MusicFx.lyrics = !MusicFx.lyrics;
        }

        function reload(): void {
            root.reload();
        }
    }
}
