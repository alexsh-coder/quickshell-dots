pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Liked state of the track playing in Spotify, read from and toggled in its page over DevTools.
// MPRIS can't do it, and the Web API needs a developer app. See scripts/spotify-like.py
Singleton {
    id: root

    readonly property MprisPlayer player: Mpris.players.values.find(p => p.desktopEntry === "spotify") ?? null
    property bool liked: false
    // Title the state belongs to, so a stale answer isn't shown for the next track
    property string title: ""
    readonly property bool known: !!player && title !== "" && title === player.trackTitle

    function toggle() {
        if (!known)
            return;
        liked = !liked;
        watcher.write("toggle\n");
    }

    Process {
        id: watcher

        command: ["python3", Quickshell.shellDir + "/scripts/spotify-like.py"]
        running: !!root.player
        stdinEnabled: true
        onRunningChanged: if (!running) root.title = ""

        stdout: SplitParser {
            onRead: line => {
                const [state, title] = line.split("\t");
                root.liked = state === "liked";
                root.title = title ?? "";
            }
        }
    }
}
