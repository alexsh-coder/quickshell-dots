pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Images are shown by awww, videos by mpvpaper on top of it (see scripts/wallpaper.sh).
// Switching to a video, a still of the old wallpaper covers the screen (WallpaperTransition)
// while the new player starts underneath, then a circle cut out of it reveals the video playing.
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

    // The still shown over a video that's starting up, and how far the circle has cut through it
    property string cover: ""
    property real reveal: 0
    property int coveredScreens: 0
    property bool covered: false
    property bool posterReady: false
    readonly property string frame: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-wallpaper-cover.jpg"
    // What the switch in progress started from
    property string from: ""
    property bool fromVideo: false

    // A switch to a video has played out
    signal settled

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
        cancel();
        from = image;
        fromVideo = video;
        current = path;
        saved.setText(video ? path : "");
        switching.restart();
        if (video) {
            prepare();
            transit();
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

    // A new pick takes over from the switch still in progress
    function cancel() {
        freeze.running = false;
        starter.running = false;
        coverTimeout.stop();
        revealAnim.stop();
        cover = "";
        reveal = 0;
        covered = false;
        posterReady = false;
    }

    // The old wallpaper goes up as a still: the image, or the frame its video is paused on
    function transit() {
        if (fromVideo) {
            freeze.path = current;
            freeze.running = true;
        } else {
            showCover(from);
        }
    }

    function showCover(still) {
        coveredScreens = 0;
        cover = still;
        if (still)
            coverTimeout.restart();
        else
            covered = true;
        startPlayer();
    }

    // Called by each screen's WallpaperTransition once the still is on it
    function coverShown() {
        if (++coveredScreens >= Quickshell.screens.length && coverTimeout.running) {
            coverTimeout.stop();
            covered = true;
            startPlayer();
        }
    }

    // Under the still: awww takes the poster, then the player starts and takes over from it
    function startPlayer() {
        if (!covered || !posterReady || starter.running)
            return;
        starter.path = current;
        starter.command = [script, "start", current, poster(current)];
        starter.running = true;
    }

    function startReveal() {
        if (cover && !revealAnim.running && reveal === 0)
            revealAnim.start();
    }

    // Both also exit when a newer switch stops them, which then must not touch it
    Process {
        id: freeze

        property string path

        command: [root.script, "freeze", root.frame]
        onExited: code => {
            if (path === root.current)
                root.showCover(code === 0 ? root.frame : root.from);
        }
    }

    Timer {
        id: coverTimeout
        interval: 500
        onTriggered: {
            root.covered = true;
            root.startPlayer();
        }
    }

    Process {
        id: starter

        property string path

        stdout: SplitParser {
            onRead: line => {
                if (line === "poster")
                    root.startReveal();
            }
        }
        onExited: {
            if (path === root.current)
                root.startReveal();
        }
    }

    // awww's grow, from the bottom with its default curve
    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: 800
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.54, 0, 0.34, 0.99, 1, 1]
        onFinished: {
            root.cover = "";
            root.reveal = 0;
            root.settled();
        }
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
            root.posterReady = true;
            root.startPlayer();
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
