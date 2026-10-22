pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Images are shown by awww, videos by mpvpaper on top of it (see scripts/wallpaper.sh).
// Switching to a video, Quickshell plays it in a circle growing over the old wallpaper, which keeps
// playing; once it covers the screen the new player starts underneath and takes over (see grows).
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

    // mpvpaper's IPC socket (see scripts/wallpaper.sh)
    readonly property string socket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-wallpaper.sock"


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
        // Videos, steps from the side and anything over a switch in progress are grown here,
        // each over the one before (see grows); awww grows the rest itself
        const stack = origin !== "bottom" || video || isVideo(path) || grows.count > 0;
        current = path;
        saved.setText(isVideo(path) || isMono(path) ? path : "");
        switching.restart();
        if (stack) {
            clock = Date.now();
            stackGrow(isVideo(path) ? path : still(path));
        }
        if (isVideo(path)) {
            prepare();
        } else {
            image = still(path);
            if (!stack)
                Quickshell.execDetached([script, "set", image, "", origin]);
        }
    }

    // Switches in flight, oldest first: each grows a circle of its image or video over the ones below.
    // Once one covers the screen awww or a new player takes it, and it and those under it go.
    // Each runs from t0 at time at (0 until it has loaded) in direction dir; a video's
    // position and duration are pos and dur (ms)
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

    // A switch has played out
    signal settled

    // A grow has covered the screen with path: what's under the grows can take it now
    signal growCovered(string path)

    function stackGrow(img) {
        grows.append({ gid: ++growSeq, path: img, under: image, origin: origin, t0: 0, at: 0, dir: 1, pos: 0, dur: 0 });
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
            root.resumeOnCue();
            if (k < 0)
                return;
            // What a grow covers can't be seen any more: no need to keep its video playing
            for (; k > 0; k--)
                root.grows.remove(0);
            const g = root.grows.get(0);
            // Newer switches still growing over it take over from it once they're done
            let newer = false;
            for (let i = 1; i < root.grows.count; i++)
                newer = newer || root.grows.get(i).dir > 0;
            if (newer || g.gid <= root.growDrop)
                return;
            root.growDrop = g.gid;
            const vid = root.isVideo(g.path);
            root.growCovered(vid ? root.poster(g.path) : g.path);
            root.cueGid = -1;
            cue.running = false;
            handOff.gid = g.gid;
            handOff.command = vid ? [root.script, "start", g.path, root.poster(g.path)] : [root.script, "set", g.path, "", "none"];
            handOff.running = false;
            handOff.running = true;
        }
    }

    // A video grow hands over to its player at the moment both show the same frame: the player
    // waits paused a little ahead of the grown copy and resumes when the copy gets there (ms)
    property int cueGid: -1
    property real cueAt: 0

    function growIndex(gid) {
        for (let i = 0; i < grows.count; i++)
            if (grows.get(i).gid === gid)
                return i;
        return -1;
    }

    function resumeOnCue() {
        if (cueGid < 0)
            return;
        const i = growIndex(cueGid);
        const pos = i < 0 ? -1 : grows.get(i).pos;
        if (pos < cueAt || pos > cueAt + 1000)
            return;
        cueGid = -1;
        Quickshell.execDetached([script, "resume"]);
        growHandOff.interval = 80;
        growHandOff.restart();
    }

    // Exits once awww has the image and a video player under the grows is gone,
    // or prints "ready" once a new player plays
    Process {
        id: handOff

        property int gid

        stdout: SplitParser {
            onRead: line => {
                const i = root.growIndex(handOff.gid);
                if (line !== "ready" || i < 0)
                    return;
                const g = root.grows.get(i);
                let at = g.pos + 600;
                if (g.dur && at > g.dur - 300)
                    at = 300;
                cue.gid = handOff.gid;
                cue.at = at;
                cue.command = [root.script, "cue", (at / 1000).toFixed(3)];
                cue.running = true;
            }
        }
        onExited: {
            if (!root.isVideo(command[2] ?? "")) {
                growHandOff.interval = 300;
                growHandOff.restart();
            }
        }
    }

    Process {
        id: cue

        property int gid
        property real at

        onExited: code => {
            if (gid !== root.growDrop)
                return;
            if (code === 0) {
                root.cueAt = at;
                root.cueGid = gid;
            } else {
                // Couldn't line them up: better a skip than the copy staying over the player
                Quickshell.execDetached([root.script, "resume"]);
                growHandOff.interval = 80;
                growHandOff.restart();
            }
        }
    }

    // awww needs a moment to show the image before the grown copy over it goes
    Timer {
        id: growHandOff
        interval: 300
        onTriggered: {
            while (root.grows.count && root.grows.get(0).gid <= root.growDrop)
                root.grows.remove(0);
            if (!root.grows.count)
                root.settled();
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
