pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Spotify's upcoming tracks, read from its page (MPRIS has no tracklist there), see
// scripts/spotify-queue.py. The last answer is kept on disk and shifted along as tracks
// change, so the list shows at once and is only re-read while someone looks at it
Singleton {
    id: root

    readonly property MprisPlayer player: SpotifyLike.player
    readonly property string script: Quickshell.shellDir + "/scripts/spotify-queue.py"
    property var tracks: []
    property string context: ""
    property bool loading: false
    property bool failed: false
    // Set while the queue view is open
    property bool watched: false
    property bool again: false

    function refresh() {
        if (!player)
            return;
        if (reader.running) {
            again = true;
            return;
        }
        loading = true;
        reader.exec(["python3", script, "list"]);
    }

    // Plays the i-th upcoming track; the list is cut right away, then re-read
    function play(i) {
        const t = tracks[i];
        if (!t || player !== SpotifyLike.player)
            return;
        tracks = tracks.slice(i);
        skipper.exec(["python3", script, "play", String(i), t.uri]);
    }

    function save() {
        cache.setText(JSON.stringify({ context, tracks }));
    }

    onWatchedChanged: if (watched) refresh()

    // The next track moving into "now playing" is the cached head, so it is dropped locally
    Connections {
        target: root.player
        function onTrackTitleChanged() {
            const now = root.player.trackTitle;
            const at = root.tracks.findIndex(t => t.title === now);
            if (at >= 0 && at < 3) {
                root.tracks = root.tracks.slice(at + 1);
                root.save();
            }
            if (root.watched)
                settle.restart();
        }
    }

    // Spotify needs a moment to update its own queue after a track change
    Timer {
        id: settle
        interval: 600
        onTriggered: root.refresh()
    }

    Process {
        id: reader

        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try {
                    data = JSON.parse(text);
                } catch (e) {}
                if (data) {
                    root.tracks = data.tracks;
                    root.context = data.context;
                    root.save();
                }
                root.failed = !data;
            }
        }
        onExited: {
            root.loading = false;
            if (root.again) {
                root.again = false;
                root.refresh();
            }
        }
    }

    Process {
        id: skipper
        onExited: settle.restart()
    }

    FileView {
        id: cache
        path: Quickshell.cachePath("spotify-queue.json")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        try {
            const c = JSON.parse(cache.text());
            tracks = c.tracks ?? [];
            context = c.context ?? "";
        } catch (e) {}
    }
}
