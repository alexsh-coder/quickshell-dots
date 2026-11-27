import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.services

// Session lock, opened with `qs ipc call lock lock`
Scope {
    id: root

    property bool locked: false
    onLockedChanged: Sfx.typingIn("lock", locked)
    property bool unlocking: false
    property string password: ""
    property bool failed: false
    readonly property bool busy: pam.active
    property real time: 0
    // Decode size for the wallpaper, shared by the preload below and every LockScreen
    // in real pixels: Qt rounds fractional scales up, so width * devicePixelRatio overshoots
    readonly property var monitors: Hyprland.monitors.values
    readonly property size wallSize: monitors.length
        ? Qt.size(Math.max(...monitors.map(m => m.width)), Math.max(...monitors.map(m => m.height)))
        : Qt.size(Math.max(...Quickshell.screens.map(s => s.width)), Math.max(...Quickshell.screens.map(s => s.height)))

    signal typed(real sign)
    signal rejected

    function lock() {
        if (locked)
            return;
        failed = false;
        password = "";
        unlocking = false;
        locked = true;
        Sfx.play("lock");
    }

    function input(text) {
        if (busy || unlocking)
            return;
        failed = false;
        password += text;
        typed(1);
    }

    function erase(all) {
        if (busy || unlocking || !password)
            return;
        password = all ? "" : password.slice(0, -1);
        typed(-1);
    }

    function submit() {
        if (password && !busy && !unlocking)
            pam.start();
    }

    PamContext {
        id: pam
        onPamMessage: {
            if (responseRequired)
                respond(root.password);
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlocking = true;
                Sfx.play("unlock");
                release.restart();
            } else {
                root.password = "";
                root.failed = true;
                Sfx.play("error");
                root.rejected();
            }
        }
    }

    // Lets the outro play before the surfaces go away; keep it longer than LockScreen's outro
    Timer {
        id: release
        interval: 950
        onTriggered: {
            root.locked = false;
            root.unlocking = false;
            root.password = "";
        }
    }

    FrameAnimation {
        running: root.locked
        onTriggered: root.time += frameTime
    }

    WlSessionLock {
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            // LockScreen fades in over the live desktop (misc:session_lock_xray) and covers it
            // fully, with an opaque backdrop of its own, once it's in
            color: "transparent"

            LockScreen {
                anchors.fill: parent
                lock: root
                wallSize: root.wallSize
                wall: root.wall
            }
        }
    }

    // The wallpaper, cut down once to the screen size (the way awww crops it), so decoding is cheap;
    // the original stands in until the copy exists, or if ImageMagick is missing
    property string wall: ""
    readonly property string wallDir: Quickshell.cachePath("lock")

    function prepareWall() {
        const src = Wallpaper.image;
        wall = src;
        if (!src)
            return;
        const size = `${wallSize.width}x${wallSize.height}`;
        shrink.target = `${wallDir}/${Qt.md5(src)}-${size}.jpg`;
        shrink.command = ["sh", "-c", 'mkdir -p "${3%/*}" && { [ -f "$3" ] || { magick "$1" -resize "$2^" -gravity center -extent "$2" -quality 95 "$3.tmp.jpg" && mv "$3.tmp.jpg" "$3"; }; }', "sh", src, size, shrink.target];
        shrink.running = true;
    }

    Connections {
        target: Wallpaper
        function onImageChanged() {
            root.prepareWall();
        }
    }

    onWallSizeChanged: prepareWall()
    Component.onCompleted: prepareWall()

    Process {
        id: shrink
        property string target
        onExited: code => {
            if (code === 0)
                root.wall = target;
        }
    }

    // Keeps the wallpaper decoded at all times, so locking never waits on it
    Image {
        source: root.wall ? "file://" + root.wall : ""
        sourceSize: root.wallSize
        asynchronous: true
    }

    // Bound in Hyprland as hl.dsp.global("quickshell:lock"): no process to spawn on the hotkey
    GlobalShortcut {
        name: "lock"
        description: "Lock the session"
        onPressed: root.lock()
    }

    IpcHandler {
        target: "lock"
        function lock(): void {
            root.lock();
        }
    }
}
