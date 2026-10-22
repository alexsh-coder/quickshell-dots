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
    // Images that hold up inverted: the picker flips each between itself and its negative
    readonly property string monoDir: dir + "/Invertible/"
    readonly property string monoCache: Quickshell.cachePath("mono")
    property var inverted: ({})
    readonly property bool mono: isMono(current)
    readonly property string script: Quickshell.shellDir + "/scripts/wallpaper.sh"

    // Edge the next switch grows from: bottom, or left/right when stepping through wallpapers
    property string origin: "bottom"

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
    // mpvpaper's IPC socket (see scripts/wallpaper.sh)
    readonly property string socket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-wallpaper.sock"
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

    function isMono(path) {
        return path.startsWith(monoDir) && !isVideo(path);
    }

    function variant(path) {
        return inverted[path] ? monoCache + "/" + Qt.md5(path) + "-neg.png" : path;
    }

    function invert(path) {
        if (!isMono(path))
            return;
        const all = Object.assign({}, inverted);
        if (all[path])
            delete all[path];
        else
            all[path] = true;
        inverted = all;
        invertedFile.setText(JSON.stringify(all, null, 1));
        if (path === current) {
            image = still(path);
            Quickshell.execDetached([script, "set", image]);
        }
    }

    function thumb(path) {
        return isVideo(path) ? poster(path) : isMono(path) ? variant(path) : path;
    }

    // What awww is given for an image
    function still(path) {
        return isMono(path) ? variant(path) : path;
    }



    function refresh() {
        if (!switching.running)
            query.running = true;
        scan.running = true;
    }

    function set(path, edge) {
        origin = edge ?? "bottom";
        // Picking the video that's on again only brings it back if its player is gone
        if (path === current && video) {
            Quickshell.execDetached([script, "play", path]);
            return;
        }
        // Image to image from the side: grown here, each switch over the one before (see grows)
        const stack = origin !== "bottom" && !video && !isVideo(path) && !cover;
        cancel();
        from = image;
        fromVideo = video;
        current = path;
        saved.setText(video || isMono(path) ? path : "");
        switching.restart();
        if (!stack)
            grows.clear();
        if (video) {
            prepare();
            transit();
        } else if (stack) {
            const img = still(path);
            clock = Date.now();
            stackGrow(img);
            image = img;
        } else {
            image = still(path);
            Quickshell.execDetached([script, "set", image, "", origin]);
        }
    }

    // Side switches in flight, oldest first: each grows a circle of its image over the ones below.
    // Once one covers the screen awww takes it without a transition, and it and those under it go.
    // Each runs from t0 at time at (0 until its image has loaded) in direction dir
    property ListModel grows: ListModel {}
    property int growSeq: 0
    property real clock: 0
    readonly property int growTime: 800
    property int growDrop: -1

    // Linear 0..1 progress
    function growT(t0, at, dir, now) {
        return at ? Math.min(1, Math.max(0, t0 + dir * ((now ?? clock) - at) / growTime)) : 0;
    }

    // Eased, for the circle's radius
    function grown(t0, at, dir) {
        const t = growT(t0, at, dir);
        return -(Math.cos(Math.PI * t) - 1) / 2;
    }

    // A grow has covered the screen with path: what's under the grows can take it now
    signal growCovered(string path)

    function stackGrow(img) {
        grows.append({ gid: ++growSeq, path: img, under: image, origin: origin, t0: 0, at: 0, dir: 1 });
    }

    Timer {
        interval: 16
        repeat: true
        running: root.grows.count > 0
        // Only checks for finished grows: clock itself ticks with the screen's frames (WallpaperTransition)
        onTriggered: {
            const now = Date.now();
            let k = -1;
            for (let i = root.grows.count - 1; i >= 0; i--) {
                const g = root.grows.get(i);
                const t = root.growT(g.t0, g.at, g.dir, now);
                // Slid all the way back: the image under it is on screen already
                if (g.at && g.dir < 0 && t <= 0)
                    root.grows.remove(i);
                else if (k < 0 && g.dir > 0 && t >= 1)
                    k = i;
            }
            const g = k >= 0 ? root.grows.get(k) : null;
            if (!g || g.gid <= root.growDrop)
                return;
            root.growDrop = g.gid;
            root.growCovered(g.path);
            Quickshell.execDetached([root.script, "set", g.path, "", "none"]);
            growHandOff.restart();
        }
    }

    // awww needs a moment to show the image before the grown copy over it goes
    Timer {
        id: growHandOff
        interval: 300
        onTriggered: {
            while (root.grows.count && root.grows.get(0).gid <= root.growDrop)
                root.grows.remove(0);
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
                } else if (last && root.isMono(last) && (still === last || still.startsWith(root.monoCache))) {
                    root.current = last;
                    root.image = root.still(last);
                    if (root.image !== still)
                        Quickshell.execDetached([root.script, "set", root.image]);
                } else {
                    root.current = root.image = still;
                }
            }
        }
    }

    Process {
        id: scan
        command: [root.script, "posters", root.posterDir, root.videoDir]
        onExited: monoScan.running = true
    }

    Process {
        id: monoScan
        command: [root.script, "mono", root.monoCache, root.monoDir]
        onExited: root.posters++
    }

    // The video or black-and-white image that's on, so it comes back after a restart
    FileView {
        id: saved
        path: Quickshell.statePath("wallpaper-video")
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: invertedFile
        path: Quickshell.statePath("inverted.json")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        try {
            inverted = JSON.parse(invertedFile.text() || "{}");
        } catch (e) {}
        refresh();
    }
}
