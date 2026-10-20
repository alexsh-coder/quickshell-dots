import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

// Session lock. `qs ipc call lock lock` snapshots every output first, so the lock can open by
// blurring the desktop itself, then locks.
Scope {
    id: root

    property bool locked: false
    property bool capturing: false
    property bool unlocking: false
    property string password: ""
    property bool failed: false
    readonly property bool busy: pam.active
    // tmpfs: fast, and the snapshot never touches the disk
    readonly property string shots: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-lock"
    // Bumped every lock; part of the snapshot name so Image never reuses an old one
    property int session: 0
    property real time: 0

    signal typed(real sign)
    signal rejected

    function lock() {
        if (locked || capturing)
            return;
        capturing = true;
        session++;
        grab.running = true;
        grabTimeout.restart();
    }

    function engage() {
        if (!capturing)
            return;
        capturing = false;
        grabTimeout.stop();
        failed = false;
        password = "";
        unlocking = false;
        locked = true;
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
                release.restart();
            } else {
                root.password = "";
                root.failed = true;
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
            Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"/*.ppm', "sh", root.shots]);
        }
    }

    Process {
        id: grab
        command: ["sh", "-c", 'd=$1; n=$2; shift 2; mkdir -p "$d"; rm -f -- "$d"/*.ppm; for o; do grim -t ppm -o "$o" "$d/$o-$n.ppm" & done; wait', "sh", root.shots, String(root.session)].concat(Quickshell.screens.map(s => s.name))
        onExited: root.engage()
    }

    // Never let a stuck screenshot keep the screen unlocked
    Timer {
        id: grabTimeout
        interval: 800
        onTriggered: root.engage()
    }

    FrameAnimation {
        running: root.locked
        onTriggered: root.time += frameTime
    }

    WlSessionLock {
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            // Opaque while locked; see-through only once the password is accepted
            color: root.unlocking ? "transparent" : "black"

            LockScreen {
                anchors.fill: parent
                lock: root
                shot: name ? `file://${root.shots}/${name}-${root.session}.ppm` : ""
                // The surface's screen doesn't expose a name, so match it by size
                readonly property string name: surface.screen?.name ?? (Quickshell.screens.find(s => s.width === surface.width && s.height === surface.height) ?? Quickshell.screens[0])?.name ?? ""
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void {
            root.lock();
        }
    }
}
