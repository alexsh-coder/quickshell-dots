pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Images are shown by awww, videos by mpvpaper on top of it (see scripts/wallpaper.sh)
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: (Quickshell.env("XDG_PICTURES_DIR") || home + "/Pictures") + "/Wallpapers"
    readonly property string videoDir: (Quickshell.env("XDG_VIDEOS_DIR") || home + "/Videos") + "/Wallpapers"
    readonly property var filters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp", "*.mp4", "*.webm", "*.mkv", "*.mov"]
    readonly property string posterDir: Quickshell.cachePath("posters")
    readonly property string script: Quickshell.shellDir + "/scripts/wallpaper.sh"

    // What was picked, an image or a video
    property string current: ""
    readonly property bool video: isVideo(current)
    // A still of it for colours, the lock screen and the overview: the image, or the video's first frame
    property string image: ""
    // Bumped when new posters land, so thumbnails that failed to load can retry
    property int posters: 0

    function isVideo(path) {
        return /\.(mp4|webm|mkv|mov)$/i.test(path);
    }

    function poster(path) {
        return posterDir + "/" + Qt.md5(path) + ".jpg";
    }

    function thumb(path) {
        return isVideo(path) ? poster(path) : path;
    }

    function refresh() {
        if (!switching.running)
            query.running = true;
        scan.running = true;
    }

    function set(path) {
        // Picking the video that's on again only brings it back if its player is gone
        if (path === current && video) {
            Quickshell.execDetached([script, "play", path]);
            return;
        }
        current = path;
        saved.setText(video ? path : "");
        switching.restart();
        if (video) {
            prepare();
        } else {
            image = path;
            Quickshell.execDetached([script, "set", path]);
        }
    }

    // The poster has to exist before anything reads it as the wallpaper
    function prepare() {
        if (prep.running)
            return;
        prep.path = current;
        prep.command = [script, "poster", current, poster(current)];
        prep.running = true;
    }

    // awww briefly shows other stills while a switch plays out
    Timer {
        id: switching
        interval: 2500
    }

    Process {
        id: prep

        property string path

        onExited: code => {
            if (path !== root.current) {
                if (root.video)
                    root.prepare();
                return;
            }
            if (code !== 0)
                return;
            root.image = root.poster(path);
            root.posters++;
            Quickshell.execDetached([root.script, "set", path, root.image]);
        }
    }

    Process {
        id: query
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/image: (.+)$/m);
                const still = m ? m[1].trim().replace(/^~/, root.home) : "";
                const last = saved.text().trim();
                if (last && still === root.poster(last)) {
                    root.current = last;
                    root.image = still;
                    Quickshell.execDetached([root.script, "play", last]);
                } else {
                    root.current = root.image = still;
                }
            }
        }
    }

    Process {
        id: scan
        command: [root.script, "posters", root.posterDir, root.videoDir]
        onExited: root.posters++
    }

    // The video that's on, so it comes back after a restart
    FileView {
        id: saved
        path: Quickshell.statePath("wallpaper-video")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: refresh()
}
