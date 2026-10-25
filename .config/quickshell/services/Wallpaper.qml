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
    // Images that are already black and white, left alone by bw mode
    property bool bw: false
    property var natural: ({})
    readonly property bool mono: isMono(current)
    readonly property string script: Quickshell.shellDir + "/scripts/wallpaper.sh"

    // Edge the next switch grows from: bottom, or left/right when stepping through wallpapers
    property string origin: "bottom"

    // Transition styles, in the order of their modes in shaders/wallswap.frag. Those with old set
    // move or distort the old wallpaper, so they get a still of it when there is one; glitch ones
    // are listed apart in the settings window
    readonly property var transitions: [
        { name: "circle", label: "Circle", icon: "radio_button_unchecked" },
        { name: "slide", label: "Slide", icon: "view_carousel", old: true },
        { name: "wipe", label: "Wipe", icon: "swipe_right" },
        { name: "fade", label: "Fade", icon: "gradient" },
        { name: "burn", label: "Burn", icon: "local_fire_department" },
        { name: "pixels", label: "Pixels", icon: "grid_view", old: true },
        { name: "glitch", label: "Glitch", icon: "broken_image", old: true, glitch: true },
        { name: "curl", label: "Page curl", icon: "auto_stories", old: true },
        { name: "tear", label: "Tear", icon: "content_cut", old: true },
        { name: "blinds", label: "Blinds", icon: "blinds", old: true },
        { name: "honeycomb", label: "Honeycomb", icon: "hexagon" },
        { name: "ripple", label: "Ripple", icon: "water", old: true },
        { name: "swirl", label: "Swirl", icon: "cyclone", old: true },
        { name: "signal", label: "Signal", icon: "settings_input_antenna", old: true, glitch: true },
        { name: "dust", label: "Dust", icon: "grain", old: true },
        { name: "dream", label: "Dream", icon: "blur_on", old: true },
        { name: "lens", label: "Black hole", icon: "trip_origin", old: true },
        { name: "kaleido", label: "Kaleidoscope", icon: "filter_vintage", old: true },
        { name: "rgb", label: "RGB split", icon: "invert_colors", old: true },
        { name: "watercolor", label: "Watercolor", icon: "water_drop" },
        { name: "speedlines", label: "Speed lines", icon: "speed" },
        { name: "tiles", label: "Flip tiles", icon: "flip", old: true },
        { name: "sakura", label: "Sakura", icon: "local_florist" },
        { name: "datamosh", label: "Datamosh", icon: "movie", old: true, glitch: true },
        { name: "pixelsort", label: "Pixel sort", icon: "bar_chart", old: true, glitch: true },
        { name: "corrupt", label: "Corrupt", icon: "report", old: true, glitch: true },
        { name: "slices", label: "Slices", icon: "view_stream", old: true, glitch: true },
        { name: "crt", label: "CRT", icon: "tv", old: true, glitch: true }
    ]

    // Modes "random" (glitch false) or "random-glitch" picks from: its group, minus those left out
    // in the settings window, or the whole group if that leaves none
    function randomPool(glitch) {
        const skip = glitch ? Settings.glitchSkip : Settings.randomSkip;
        const group = transitions.map((t, i) => i).filter(i => !!transitions[i].glitch === glitch);
        const pool = group.filter(i => !skip.includes(transitions[i].name));
        return pool.length ? pool : group;
    }

    // Mode for the next switch: the chosen style, or a random one other than the last
    property int lastFx: 0
    function pickFx() {
        const i = transitions.findIndex(t => t.name === Settings.transition);
        if (i >= 0)
            return i;
        let pool = randomPool(Settings.transition === "random-glitch");
        if (pool.length > 1)
            pool = pool.filter(m => m !== lastFx);
        return pool[Math.floor(Math.random() * pool.length)];
    }

    // Still of a video's current frame, for transitions that need the old wallpaper
    readonly property string frozen: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-wallpaper-old.jpg"

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

    function canGray(path) {
        return !!path && !isMono(path) && !natural[path];
    }

    // The poster awww holds under a video
    function videoStill(path) {
        return bw ? poster(path).replace(/\.jpg$/, "-gray.jpg") : poster(path);
    }

    function grayPath(path) {
        return monoCache + "/" + Qt.md5(path) + "-gray.jpg";
    }

    // Black-and-white mode for every image at once. Copies are made ahead by the scan; the one on screen
    // is made first if missing, so awww never gets a file that isn't there yet
    function toggleGray() {
        if (!bw && canGray(current) && !isVideo(current))
            grayJob.createObject(root, { path: current });
        else
            setBw(!bw);
    }

    function setBw(on) {
        bw = on;
        bwFile.setText(on ? "1" : "");
        if (video) {
            // The player is recoloured in place; awww's poster swaps underneath
            bwSync.command = [script, "bw", on ? "on" : "off", poster(current)];
            bwSync.running = true;
        } else {
            Quickshell.execDetached([script, "bw", on ? "on" : "off"]);
            if (canGray(current))
                set(current);
        }
    }

    Process {
        id: bwSync
        onExited: if (root.video) root.image = root.videoStill(root.current)
    }

    Component {
        id: grayJob

        Process {
            required property string path

            running: true
            command: [root.script, "gray", path, root.monoCache]
            onExited: code => {
                if (code === 0)
                    root.setBw(true);
                destroy();
            }
        }
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
        if (path === current)
            set(path);
    }

    function thumb(path) {
        return isVideo(path) ? (bw && canGray(path) ? videoStill(path) : poster(path)) : still(path);
    }

    // What awww is given for an image
    function still(path) {
        return isMono(path) ? variant(path) : bw && canGray(path) ? grayPath(path) : path;
    }



    function refresh() {
        if (!switching.running)
            query.running = true;
        scan.running = true;
    }

    // Starting from the cursor asks Hyprland where it is first
    function set(path, edge) {
        if (Settings.transitionFrom !== "cursor")
            return void apply(path, edge, null);
        cursor.path = path;
        cursor.edge = edge ?? "bottom";
        cursor.running = false;
        cursor.running = true;
    }

    Process {
        id: cursor

        property string path
        property string edge

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = null;
                try {
                    const c = JSON.parse(text);
                    p = Qt.point(c.x, c.y);
                } catch (e) {}
                root.apply(cursor.path, cursor.edge, p);
            }
        }
    }

    // point: where the cursor is, in Hyprland's global pixels, when the switch starts there
    function apply(path, edge, point) {
        origin = edge ?? "bottom";
        // Picking the video that's on again only brings it back if its player is gone
        if (path === current && video) {
            Quickshell.execDetached([script, "play", path]);
            return;
        }
        const fx = pickFx();
        lastFx = fx;
        // What's on screen right now, if nothing is moving: what the transition starts from
        const settledOld = grows.count === 0 && !native.running;
        const old = !transitions[fx].old || !settledOld ? "" : video ? frozen : image;
        // Videos, steps from the side, other styles and anything over a switch in progress (awww's own
        // grow included: restarting it mid-way stalls it) are grown here, each over the one before
        // (see grows); so is any switch under live music effects, which would drop out for awww's.
        // awww grows the rest itself
        const fxLive = MusicFx.wallpaperFx && Cava.active;
        const stack = origin !== "bottom" || fx !== 0 || point || video || isVideo(path) || grows.count > 0 || native.running || fxLive;
        current = path;
        saved.setText(isVideo(path) || isMono(path) || bw && canGray(path) ? path : "");
        switching.restart();
        if (stack) {
            clock = Date.now();
            stackGrow(isVideo(path) ? path : still(path), fx, old, point);
        }
        if (isVideo(path)) {
            prepare();
        } else {
            image = still(path);
            if (!stack) {
                native.restart();
                Quickshell.execDetached([script, "set", image, "", origin, (Settings.durationOf("circle") / 1000).toFixed(2)]);
            }
        }
    }

    // awww's own grow is running
    Timer {
        id: native
        interval: Settings.durationOf("circle") + 100
    }

    // Switches in flight, oldest first: each grows a circle of its image or video over the ones below.
    // Once one covers the screen awww or a new player takes it, and it and those under it go.
    // Each runs from t0 at time at (0 until it has loaded) in direction dir; a video's
    // position and duration are pos and dur (ms)
    property ListModel grows: ListModel {}
    property int growSeq: 0
    property real clock: 0
    property int growDrop: -1

    // Linear 0..1 progress over ms, the switch's own length
    function growT(t0, at, dir, now, ms) {
        return at ? Math.min(1, Math.max(0, t0 + dir * ((now ?? clock) - at) / (ms || Settings.transitionTime))) : 0;
    }

    // Eased, for the circle's radius
    function grown(t0, at, dir) {
        const t = growT(t0, at, dir);
        return -(Math.cos(Math.PI * t) - 1) / 2;
    }

    // The empty desktop was clicked to change the wallpaper (DeskClick)
    signal randomRequested

    // A switch has played out
    signal settled

    // A grow has covered the screen with path: what's under the grows can take it now
    signal growCovered(string path)

    // A newly started video player is playing and listens on socket
    signal playerReady

    // old is the still under it for transitions that move it; for a video, its frame once frozen (wait)
    function stackGrow(img, fx, old, point) {
        const wait = old === frozen;
        grows.append({ gid: ++growSeq, path: img, under: image, origin: origin, fx: fx, old: wait ? "" : old, wait: wait,
            px: point ? point.x : -1e6, py: point ? point.y : -1e6, ms: Settings.durationOf(transitions[fx].name), t0: 0, at: 0, dir: 1, pos: 0, dur: 0 });
        if (wait) {
            freeze.gid = growSeq;
            freeze.running = false;
            freeze.running = true;
        }
    }

    Process {
        id: freeze

        property int gid

        command: [root.script, "freeze", root.frozen]
        onExited: code => {
            const i = root.growIndex(gid);
            if (i < 0)
                return;
            if (code === 0)
                root.grows.setProperty(i, "old", root.frozen);
            root.grows.setProperty(i, "wait", false);
        }
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
                const t = root.growT(g.t0, g.at, g.dir, now, g.ms);
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
                if (line === "ready")
                    root.playerReady();
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
        prep.command = [script, "still", current, poster(current)];
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
            root.image = root.videoStill(path);
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
                if (last && root.isVideo(last) && (still === root.poster(last) || still === root.videoStill(last))) {
                    root.current = last;
                    root.image = root.videoStill(last);
                    Quickshell.execDetached([root.script, "play", last]);
                } else if (last && (root.isMono(last) || root.bw && root.canGray(last)) && (still === last || still.startsWith(root.monoCache))) {
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
        onExited: {
            root.posters++;
            grayScan.running = true;
        }
    }

    Process {
        id: grayScan
        command: [root.script, "grays", root.monoCache, root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const all = {};
                for (const f of text.split("\n"))
                    if (f)
                        all[f] = true;
                root.natural = all;
            }
        }
    }

    // The video, inverted or black-and-white image that's on, so it comes back after a restart
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

    FileView {
        id: bwFile
        path: Quickshell.statePath("bw")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        try {
            inverted = JSON.parse(invertedFile.text() || "{}");
        } catch (e) {}
        bw = bwFile.text().trim() === "1";
        // The script keeps its own flag in the runtime dir, gone after a reboot
        Quickshell.execDetached([script, "bw", bw ? "on" : "off"]);
        refresh();
    }

    // The login screen follows the wallpaper and accent once they settle, so flipping through
    // wallpapers only syncs the last one (extras/sddm)
    Timer {
        id: loginSync
        interval: 5000
        onTriggered: if (root.image) Quickshell.execDetached(["sudo", "-n", "/usr/local/bin/sddm-rice-sync", root.image, Accent.color.toString()])
    }

    onImageChanged: loginSync.restart()

    Connections {
        target: Accent
        function onColorChanged() { loginSync.restart(); }
    }
}
