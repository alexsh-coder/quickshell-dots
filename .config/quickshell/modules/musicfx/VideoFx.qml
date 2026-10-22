import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// Zoom and shake for a video wallpaper. mpvpaper draws it out of reach of Quickshell,
// so the motion is sent to its mpv as video-zoom and video-pan over the IPC socket.
Scope {
    id: root

    readonly property bool active: (MusicFx.zoom || MusicFx.shake) && Cava.active && Wallpaper.video
    readonly property var screen: Quickshell.screens[0]
    readonly property real refresh: Hyprland.monitorFor(screen)?.lastIpcObject?.refreshRate || 60

    property real zoom: 0
    property real panX: 0
    property real panY: 0
    property var sent: ({})
    property int retry: 0
    property Socket sock: null

    function send(key, value) {
        if (sent[key] === value)
            return false;
        sent[key] = value;
        sock.write(JSON.stringify({ command: ["set_property", key, value] }) + "\n");
        return true;
    }

    // A Socket whose peer went away can keep reporting itself connected, so each player gets a new one
    function drop(s) {
        if (s !== sock)
            return;
        sock?.destroy();
        sock = null;
        retry = 30;
    }

    function round(v) {
        return Math.round(v * 10000) / 10000;
    }

    function tick() {
        if (active) {
            const w = screen?.width || 1920, h = screen?.height || 1080;
            const t = Date.now() / 1000;
            // Same curves as WallpaperFx, with pixels turned into fractions of the frame
            const amp = MusicFx.shake ? Cava.kick * Cava.kick * 14 * MusicFx.gain("shake") : 0;
            zoom = (MusicFx.zoom ? Cava.bass * 0.04 * MusicFx.gain("zoom") : 0) + amp * 2 / Math.min(w, h);
            panX = amp * (Math.sin(t * 47) * 0.6 + Math.sin(t * 83 + 1.3) * 0.4) / w;
            panY = amp * (Math.sin(t * 53 + 2.1) * 0.6 + Math.sin(t * 71 + 0.4) * 0.4) / h;
        } else {
            // Eases back instead of snapping when the music stops
            zoom *= 0.85;
            panX *= 0.85;
            panY *= 0.85;
            if (zoom < 0.0005) {
                zoom = panX = panY = 0;
            }
        }

        // mpvpaper is restarted with every video, so keep trying while there is something to send.
        // A refused connection fails before createObject returns, so a socket that hasn't
        // connected by the next try is replaced too.
        if (!sock?.connected) {
            if (retry-- <= 0) {
                sock?.destroy();
                sent = {};
                retry = 30;
                sock = link.createObject(root);
            }
            return;
        }
        // By default mpv redraws only on new video frames, half the refresh rate or less, and the
        // motion stutters. Display sync redraws on every refresh, so it's on only while moving.
        const moving = active || zoom > 0;
        let changed = send("display-fps-override", Math.round(refresh * 1000) / 1000);
        changed = send("video-sync", moving ? "display-resample" : "audio") || changed;
        // video-zoom is a power of two
        changed = send("video-zoom", round(Math.log2(1 + zoom))) || changed;
        changed = send("video-pan-x", round(panX)) || changed;
        changed = send("video-pan-y", round(panY)) || changed;
        if (changed)
            sock.flush();
    }

    // A fresh link right away when an effect turns on, instead of waiting out the retry
    // on a socket that may have gone stale while idle.
    // The last tick puts mpv back to its own sync, even when there was nothing to ease back.
    onActiveChanged: {
        if (active) {
            sock?.destroy();
            sent = {};
            retry = 30;
            sock = link.createObject(root);
        }
        tick();
    }

    Timer {
        interval: 16
        repeat: true
        running: root.active || root.zoom > 0
        onTriggered: root.tick()
    }

    // The old player quits as soon as another video is picked
    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            root.drop(root.sock);
        }
    }

    Component {
        id: link

        Socket {
            id: s

            path: Wallpaper.socket
            connected: true
            parser: SplitParser {}
            onError: root.drop(s)
            onConnectedChanged: if (!connected) root.drop(s)
        }
    }
}
