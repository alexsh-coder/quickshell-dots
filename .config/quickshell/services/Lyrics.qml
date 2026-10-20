pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Time-synced lyrics for the active MPRIS player, fetched from lrclib.net
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

    function parse(lrc) {
        const out = [];
        for (const raw of (lrc ?? "").split("\n")) {
            const text = raw.replace(/\[[^\]]*\]/g, "").trim();
            const re = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
            let m;
            while ((m = re.exec(raw)))
                out.push({ time: +m[1] * 60 + +m[2], text: text });
        }
        out.sort((a, b) => a.time - b.time);
        if (out.length && out[0].time > 0)
            out.unshift({ time: 0, text: "" });
        return out;
    }

    function pick(json) {
        const items = Array.isArray(json) ? json : [json];
        const len = player?.length ?? 0;
        const synced = items.filter(i => i?.syncedLyrics);
        synced.sort((a, b) => Math.abs(a.duration - len) - Math.abs(b.duration - len));
        return synced[0]?.syncedLyrics ?? "";
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
            fetch.exec(["sh", "-c", `
                curl -sf -m 10 -G "$1/get" --data-urlencode "artist_name=$2" --data-urlencode "track_name=$3" \
                    --data-urlencode "album_name=$4" --data-urlencode "duration=$5" ||
                curl -sf -m 10 -G "$1/search" --data-urlencode "artist_name=$2" --data-urlencode "track_name=$3"`,
                "sh", "https://lrclib.net/api", p.trackArtist, p.trackTitle, p.trackAlbum, String(Math.round(p.length))]);
        }
    }

    Process {
        id: fetch
        property string reqKey
        stdout: StdioCollector {
            onStreamFinished: {
                let lines;
                try {
                    lines = root.parse(root.pick(JSON.parse(text)));
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
}
