import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Super+Tab: the desktop pulls back and every window lands on a slowly turning ring.
// The scene starts as an exact copy of the screen and ends as one, so both ways are seamless.
Scope {
    id: root

    onShownChanged: Sfx.play(shown ? "open" : "close")

    // closed -> loading (waiting for hyprctl and a screen frame) -> open -> closing
    property string phase: "closed"
    readonly property bool shown: phase !== "closed"

    property var entries: []
    property var monitor: null
    property string monitorName: ""
    property bool built: false
    property bool frameReady: false
    property bool timedOut: false
    // Windows that sit flat at their real place when progress is 0
    property var flatSet: []
    property var openFlatSet: []
    property bool captureValid: true

    // 0 = the real desktop, 1 = the ring
    property real progress: 0
    // Ring rotation in windows: target is where it heads, pos follows on a spring
    property real target: 0
    property real pos: 0
    property real vel: 0
    property real time: 0

    // Super+Tab pressed again while open: releasing Super picks, like Alt+Tab
    property bool armed: false
    // The cursor is warped back to the centre near the edges, so travel is summed into virtualX
    property bool tracking: false
    property real virtualX: 0
    property real anchorX: 0
    property real anchorTarget: 0
    property real lastX: 0
    property bool warping: false
    property bool warped: false
    property real warpX: 0
    property point startCursor
    property real wheelAcc: 0

    // Textures the cards borrow: what sits behind see-through windows, and the screen as it was
    readonly property Item softWall: softWall
    readonly property Item screenFrame: capLoader.item
    // The wallpaper copies are decoded only while shown, so they don't sit in memory between uses
    readonly property bool wallsReady: [wall, softWall, blurWall].every(i => i.status !== Image.Loading)
    onWallsReadyChanged: maybeBegin()

    readonly property int count: entries.length
    readonly property bool wraps: count >= 3
    readonly property int selectedIndex: count ? ((Math.round(target) % count) + count) % count : -1
    readonly property var selected: selectedIndex >= 0 ? entries[selectedIndex] : null

    readonly property var screen: Quickshell.screens.find(s => s.name === monitorName) ?? Quickshell.screens[0]
    // Hyprland's pixels per overlay pixel: the panel scale (QT_SCALE_FACTOR) shrinks the overlay's
    readonly property real ui: Number(Quickshell.env("QT_SCALE_FACTOR") || 1)
    readonly property real originX: (monitor?.reserved?.[0] ?? 0) / ui
    readonly property real originY: (monitor?.reserved?.[1] ?? 0) / ui

    // Scene geometry, in overlay pixels
    property real sceneW: 1
    property real sceneH: 1
    readonly property real cx: sceneW / 2
    readonly property real cy: sceneH * 0.44
    readonly property real boxW: sceneW * 0.42
    readonly property real boxH: sceneH * 0.5
    readonly property real focal: 1400
    readonly property real step: 40 * Math.PI / 180
    // Radius that puts the neighbours just behind the centre window's edges
    readonly property real radius: boxW * 0.8 / (Math.sin(step) - boxW * 0.8 * (1 - Math.cos(step)) / focal)
    readonly property real pxPerWindow: 160

    function norm(addr) {
        return String(addr).replace(/^0x/, "");
    }

    // Position of window i on the ring relative to the front, wrapped into the visible arc
    function slot(i) {
        const p = i - pos;
        if (!wraps)
            return p;
        return p - count * Math.round(p / count);
    }

    function visibility(p) {
        const limit = wraps ? Math.min(2, count / 2) : 2;
        return Math.max(0, Math.min(1, (limit - Math.abs(p)) / 0.5));
    }

    function ringPose(e, p) {
        const a = p * step + 0.02 * Math.sin(time * 0.5);
        return {
            x: radius * Math.sin(a),
            y: 6 * Math.sin(time * 0.8),
            d: radius * (1 - Math.cos(a)),
            a: a,
            k: Math.min(boxW / e.w, boxH / e.h),
            op: visibility(p)
        };
    }

    function pose(e, p, flat, t) {
        const r = ringPose(e, p);
        const s = flat
            ? { x: e.x + e.w / 2 - cx, y: e.y + e.h / 2 - cy, d: 0, a: 0, k: 1, op: 1 }
            : { x: r.x, y: r.y, d: r.d + 900, a: r.a, k: r.k, op: 0 };
        const mix = (u, v) => u + (v - u) * t;
        return {
            x: mix(s.x, r.x),
            y: mix(s.y, r.y),
            // Flat windows lift off the screen in a slight arc instead of a straight line
            d: mix(s.d, r.d) + (flat ? 160 * Math.sin(Math.PI * t) : 0),
            a: mix(s.a, r.a),
            k: mix(s.k, r.k),
            op: mix(s.op, r.op)
        };
    }

    // Item (u, v) -> scale k, turn a around the vertical axis, move to (x, y, depth d), project.
    // The z row stays identity so the matrix remains invertible for input mapping.
    function matrix(q, w, h) {
        const kc = q.k * Math.cos(q.a);
        const ks = q.k * Math.sin(q.a);
        const w0 = 1 + (q.d - ks * w / 2) / focal;
        return Qt.matrix4x4(
            kc + cx * ks / focal, 0, 0, -kc * w / 2 + q.x + cx * w0,
            cy * ks / focal, q.k, 0, -q.k * h / 2 + q.y + cy * w0,
            0, 0, 1, 0,
            ks / focal, 0, 0, w0);
    }

    function setTarget(v) {
        target = wraps ? v : Math.max(0, Math.min(count - 1, v));
        return target !== v;
    }

    function stepBy(d) {
        if (phase !== "open")
            return;
        setTarget(Math.round(target) + d);
        anchorX = virtualX;
        anchorTarget = target;
    }

    function toGlobal(x, y) {
        return Qt.point(Math.round((monitor?.x ?? 0) + (originX + x) * ui), Math.round((monitor?.y ?? 0) + (originY + y) * ui));
    }

    function warpCursor(p) {
        Hyprland.dispatch(`hl.dsp.cursor.move({ x = ${p.x}, y = ${p.y} })`);
    }

    function mouseMoved(x, y) {
        if (!tracking) {
            tracking = true;
            startCursor = toGlobal(x, y);
            lastX = virtualX = anchorX = x;
            anchorTarget = Math.round(target);
            return;
        }
        // The jump caused by our own warp isn't movement
        if (warping && Math.abs(x - warpX) < 40 && Math.abs(x - lastX) > 100) {
            warping = false;
            lastX = x;
            return;
        }
        virtualX += x - lastX;
        lastX = x;
        if (phase !== "open")
            return;
        // The ring follows the cursor, as if dragged
        if (setTarget(anchorTarget - (virtualX - anchorX) / pxPerWindow)) {
            anchorX = virtualX;
            anchorTarget = target;
        }
        settle.restart();
        if (!warping && Math.abs(x - sceneW / 2) > sceneW * 0.3) {
            warping = warped = true;
            warpX = sceneW / 2;
            warpReset.restart();
            warpCursor(toGlobal(warpX, y));
        }
    }

    function pick(i) {
        if (phase !== "open")
            return;
        const cur = selectedIndex;
        if (i === cur) {
            activate();
            return;
        }
        let d = i - cur;
        if (wraps)
            d -= count * Math.round(d / count);
        stepBy(d);
    }

    function show() {
        if (shown)
            return;
        phase = "loading";
        monitorName = Hyprland.focusedMonitor?.name ?? "";
        built = frameReady = timedOut = false;
        progress = 0;
        target = pos = vel = 0;
        armed = false;
        tracking = warping = warped = false;
        wheelAcc = 0;
        query.running = true;
        loadTimeout.restart();
        // qs may have started before awww-daemon and missed the wallpaper
        if (!Wallpaper.current)
            Wallpaper.refresh();
    }

    function build(clients, monitors) {
        const mon = monitors.find(m => m.focused) ?? monitors[0];
        const visibleWs = [mon.activeWorkspace?.id, mon.specialWorkspace?.id].filter(id => id);
        const tls = Hyprland.toplevels.values;
        monitor = mon;
        entries = clients
            .filter(c => c.mapped && c.size[0] > 0 && c.size[1] > 0)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)
            .map(c => ({
                address: c.address,
                toplevel: tls.find(t => norm(t.address) === norm(c.address))?.wayland ?? null,
                title: c.title,
                appClass: c.class,
                x: (c.at[0] - mon.x - (mon.reserved?.[0] ?? 0)) / ui,
                y: (c.at[1] - mon.y - (mon.reserved?.[1] ?? 0)) / ui,
                w: c.size[0] / ui,
                h: c.size[1] / ui,
                ws: c.workspace.id,
                onScreen: c.monitor === mon.id && visibleWs.includes(c.workspace.id) && !c.hidden
            }));
        openFlatSet = entries.filter(e => e.onScreen).map(e => e.address);
        flatSet = openFlatSet;
        captureValid = true;
        built = true;
        maybeBegin();
    }

    function maybeBegin() {
        if (phase !== "loading" || !built || !((frameReady && wallsReady) || timedOut))
            return;
        if (!count) {
            phase = "closed";
            return;
        }
        phase = "open";
        anim.from = progress;
        anim.to = 1;
        anim.duration = 650;
        anim.restart();
        stage.forceActiveFocus();
    }

    // e: the window to land on, or null to go back to how things were
    function close(e) {
        if (phase !== "open")
            return;
        // Hand the pointer back where it was picked up
        if (warped)
            warpCursor(startCursor);
        if (e && !e.onScreen) {
            const special = e.ws < 0;
            flatSet = entries
                .filter(o => o.ws === e.ws || (special && openFlatSet.includes(o.address) && o.ws > 0))
                .map(o => o.address);
            captureValid = false;
        } else {
            flatSet = openFlatSet;
            captureValid = true;
        }
        if (e)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${e.address}" })`);
        setTarget(Math.round(target));
        phase = "closing";
        anim.from = progress;
        anim.to = 0;
        anim.duration = 480;
        anim.restart();
    }

    function activate() {
        close(selected);
    }

    NumberAnimation {
        id: anim

        target: root
        property: "progress"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.emphasizedDecel
        onFinished: {
            if (root.phase === "closing") {
                root.phase = "closed";
                root.entries = [];
            }
        }
    }

    Process {
        id: query

        command: ["sh", "-c", "printf '[%s,%s]' \"$(hyprctl -j clients)\" \"$(hyprctl -j monitors)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const [clients, monitors] = JSON.parse(text);
                    root.build(clients, monitors);
                } catch (err) {
                    console.warn("overview:", err);
                    root.phase = "closed";
                }
            }
        }
    }

    // Starts without the screen frame if it doesn't arrive in time
    Timer {
        id: loadTimeout
        interval: 250
        onTriggered: {
            root.timedOut = true;
            root.maybeBegin();
        }
    }

    // Mouse stopped: snap to the nearest window
    Timer {
        id: settle
        interval: 160
        onTriggered: {
            root.setTarget(Math.round(root.target));
            root.anchorX = root.virtualX;
            root.anchorTarget = root.target;
        }
    }

    // In case the warp's motion event never shows up
    Timer {
        id: warpReset
        interval: 250
        onTriggered: root.warping = false
    }

    FrameAnimation {
        running: root.shown
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            root.time += dt;
            // Slightly underdamped: the ring glides in and settles with a hint of overshoot
            const k = 170;
            const c = 2 * Math.sqrt(k) * 0.85;
            root.vel += (k * (root.target - root.pos) - c * root.vel) * dt;
            root.pos += root.vel * dt;
        }
    }


    function cycle(d) {
        if (phase === "open") {
            stepBy(d);
            armed = true;
        } else {
            show();
        }
    }

    GlobalShortcut {
        name: "overview"
        description: "Window overview, next window"
        onPressed: root.cycle(1)
    }

    GlobalShortcut {
        name: "overview-back"
        description: "Window overview, previous window"
        onPressed: root.cycle(-1)
    }

    IpcHandler {
        target: "overview"

        function toggle(): void {
            if (root.phase === "open")
                root.close(null);
            else
                root.show();
        }

        function next(): void { root.cycle(1); }
        function back(): void { root.cycle(-1); }
    }

    PanelWindow {
        id: win

        visible: root.shown
        screen: root.screen

        WlrLayershell.namespace: "overview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Stays below the bar, which keeps living on top
        exclusionMode: ExclusionMode.Normal
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        onWidthChanged: root.sceneW = width
        onHeightChanged: root.sceneH = height
        Component.onCompleted: {
            root.sceneW = width;
            root.sceneH = height;
        }

        Item {
            id: stage

            anchors.fill: parent
            // Nothing is drawn until the scene can match the screen
            opacity: root.phase === "loading" ? 0 : 1
            focus: true

            Keys.onPressed: event => {
                const shift = event.modifiers & Qt.ShiftModifier;
                if (event.key === Qt.Key_Escape)
                    root.close(null);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                    root.activate();
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !shift))
                    root.stepBy(1);
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
                    root.stepBy(-1);
                else
                    return;
                event.accepted = true;
            }
            Keys.onReleased: event => {
                if (root.armed && (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta))
                    root.activate();
            }

            // The desktop under the windows: wallpaper, sharp then blurred and dimmed
            Item {
                id: backdrop

                x: -root.originX
                y: -root.originY
                width: root.screen?.width ?? win.width
                height: root.screen?.height ?? win.height

                // Stand-in for Hyprland's light blur behind see-through windows like kitty
                Image {
                    id: softWall

                    anchors.fill: parent
                    source: wall.source
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    layer.enabled: root.shown
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 16
                        blur: 0.6
                        brightness: -0.06
                    }
                }

                Image {
                    id: wall

                    anchors.fill: parent
                    source: root.shown && Wallpaper.image ? "file://" + Wallpaper.image : ""
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    // Decoded off the main thread: a wallpaper switch would freeze the shell for a frame or few
                    asynchronous: true
                    cache: false
                }

                // Static blur, crossfaded in: animating the blur radius itself steps visibly
                Image {
                    id: blurWall

                    anchors.fill: parent
                    source: wall.source
                    sourceSize: Qt.size(width / 2, height / 2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    opacity: root.progress
                    layer.enabled: root.shown
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 64
                        blur: 1
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: 0.35 * root.progress
                }

                // Frozen frame of the screen as it was: covers the pop when the scene appears
                Loader {
                    id: capLoader

                    anchors.fill: parent
                    active: root.shown
                    opacity: root.captureValid ? Math.max(0, 1 - root.progress / 0.35) : 0

                    sourceComponent: ScreencopyView {
                        captureSource: root.screen
                        live: false
                        paintCursor: false
                        onHasContentChanged: {
                            root.frameReady = hasContent;
                            root.maybeBegin();
                        }
                    }
                }
            }

            MouseArea {
                onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                onReleased: if (containsMouse) Sfx.tap("click")
                anchors.fill: parent
                hoverEnabled: true
                // The ring itself is the pointer here
                cursorShape: Qt.BlankCursor
                onPositionChanged: mouse => root.mouseMoved(mouse.x, mouse.y)
                onClicked: root.close(null)
                onWheel: wheel => {
                    root.wheelAcc += wheel.angleDelta.y || wheel.angleDelta.x;
                    while (Math.abs(root.wheelAcc) >= 120) {
                        const d = root.wheelAcc > 0 ? -1 : 1;
                        root.wheelAcc += d * 120;
                        root.stepBy(d);
                    }
                }
            }

            Item {
                anchors.fill: parent

                Repeater {
                    model: root.entries

                    WindowCard {
                        overview: root
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 48
                width: Math.min(parent.width - 96, 720)
                spacing: 4
                opacity: root.phase === "open" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Medium
                    color: "#e6edf3"
                    text: root.selected?.title ?? ""
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Qt.alpha("#e6edf3", 0.55)
                    text: root.selected ? `${root.selectedIndex + 1} / ${root.count}` : ""
                }
            }
        }
    }
}
