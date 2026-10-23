pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Spotify's played, current and upcoming tracks, read from its page (MPRIS has no tracklist there), see
// scripts/spotify-queue.py. The last answer is kept on disk and shifted along as tracks
// change, so the list shows at once and is only re-read while someone looks at it
Singleton {
    id: root

    readonly property MprisPlayer player: SpotifyLike.player
    readonly property string script: Quickshell.shellDir + "/scripts/spotify-queue.py"
    property var tracks: []
    // Index of the playing track in tracks
    property int current: -1
    property string context: ""
    property bool loading: false
    property bool failed: false
    // Set while the queue view is open
    property bool watched: false
    property bool again: false
    // Playlists, albums and artists saved in the library, Liked Songs first
    property var library: []

    function loadLibrary() {
        if (player && !libraryReader.running)
            libraryReader.exec(["python3", script, "library"]);
    }

    function open(uri) {
        if (player === SpotifyLike.player)
            skipper.exec(["python3", script, "open", uri]);
    }

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

    // Plays the i-th track; it is marked right away, then the list is re-read
    function play(i) {
        const t = tracks[i];
        if (!t || i === current || player !== SpotifyLike.player)
            return;
        current = i;
        skipper.exec(["python3", script, "play", String(i), t.uri]);
    }

    function save() {
        cache.setText(JSON.stringify({ context, current, tracks }));
    }

    onWatchedChanged: if (watched) refresh()

    // A nearby cached track becoming "now playing" is marked locally
    Connections {
        target: root.player
        function onTrackTitleChanged() {
            const now = root.player.trackTitle;
            const from = Math.max(0, root.current - 3);
            const at = root.tracks.findIndex((t, i) => i >= from && i <= root.current + 3 && t.title === now);
            if (at >= 0) {
                root.current = at;
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
                    root.current = data.current ?? -1;
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
        id: libraryReader

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.library = JSON.parse(text);
                } catch (e) {}
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
            current = c.current ?? -1;
            context = c.context ?? "";
        } catch (e) {}
    }
}
