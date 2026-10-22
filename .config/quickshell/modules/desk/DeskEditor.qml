import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// Desktop edit mode: windows step aside, every widget gets a frame to drag and corners to resize,
// and the panel on the left edits the preset. Opened from the wallpaper picker (E), Super+D,
// quick settings, the music popover or `qs ipc call desk edit`
Scope {
    id: root

    property bool panelShown: true
    // Snap lines in use while dragging, as screen fractions
    property var guidesX: []
    property var guidesY: []
    // Band selection in progress, in px: { x0, y0, x1, y1 }
    property var band: null

    function windowsFade(mode) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/windows-fade.sh", mode]);
    }

    Connections {
        target: Desk
        function onEditingChanged() {
            root.windowsFade(Desk.editing ? "hide" : "show");
            if (Desk.editing) {
                root.panelShown = true;
                Qt.callLater(() => keys.forceActiveFocus());
            }
            Desk.preview = null;
        }
    }

    PanelWindow {
        id: win

        readonly property real sw: width
        readonly property real sh: height
        // Snapping distance and the margin kept from the screen edges, in px
        readonly property real snap: 10
        readonly property real margin: 28
        // The bar covers the top of the screen: vertical guides divide what's left below it
        readonly property real barTop: Theme.barHeight / Math.max(1, sh)
        readonly property var linesX: [1 / 3, 0.5, 2 / 3]
        readonly property var linesY: linesX.map(f => barTop + (1 - barTop) * f)

        // Snaps a span [a, b] (fractions) to the centre, thirds and edge margins; returns the shift
        // and the line it caught
        function snapSpan(a, b, size, guides, lines, lo) {
            const m = lo + margin / size;
            let best = null;
            const tryLine = (edge, line) => {
                const d = line - edge;
                if (Math.abs(d) * size < snap && (!best || Math.abs(d) < Math.abs(best.d)))
                    best = { d: d, line: line };
            };
            for (const l of lines) {
                tryLine((a + b) / 2, l);
                tryLine(a, l);
                tryLine(b, l);
            }
            tryLine(a, m);
            tryLine(b, 1 - margin / size);
            if (best)
                guides.push(best.line);
            return best ? best.d : 0;
        }

        visible: Desk.editing || stage.opacity > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.namespace: "desk-editor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Desk.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        Item {
            id: stage

            anchors.fill: parent
            opacity: Desk.editing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

            // Empty desktop: a click clears the selection, a drag picks every widget the band touches
            MouseArea {
                anchors.fill: parent
                onPressed: mouse => root.band = { x0: mouse.x, y0: mouse.y, x1: mouse.x, y1: mouse.y }
                onPositionChanged: mouse => {
                    if (root.band)
                        root.band = Object.assign({}, root.band, { x1: mouse.x, y1: mouse.y });
                }
                onReleased: mouse => {
                    const b = root.band, add = mouse.modifiers & Qt.ControlModifier;
                    root.band = null;
                    if (!b)
                        return;
                    const l = Math.min(b.x0, b.x1) / win.sw, r = Math.max(b.x0, b.x1) / win.sw;
                    const t = Math.min(b.y0, b.y1) / win.sh, d = Math.max(b.y0, b.y1) / win.sh;
                    if ((r - l) * win.sw < 4 && (d - t) * win.sh < 4) {
                        if (!add)
                            Desk.select("");
                        return;
                    }
                    Desk.selectMany(Desk.widgets.filter(w => w.x - w.w / 2 < r && w.x + w.w / 2 > l && w.y - w.h / 2 < d && w.y + w.h / 2 > t).map(w => w.id), add);
                }
                onCanceled: root.band = null
            }

            Rectangle {
                z: 5
                visible: !!root.band
                x: root.band ? Math.min(root.band.x0, root.band.x1) : 0
                y: root.band ? Math.min(root.band.y0, root.band.y1) : 0
                width: root.band ? Math.abs(root.band.x1 - root.band.x0) : 0
                height: root.band ? Math.abs(root.band.y1 - root.band.y0) : 0
                color: Qt.alpha(Theme.accent, 0.12)
                border.width: 1
                border.color: Theme.accent
            }

            // Centre and thirds, faint, for orientation
            Repeater {
                model: win.linesX

                Rectangle {
                    required property real modelData
                    x: stage.width * modelData
                    width: 1
                    height: stage.height
                    color: Qt.alpha(Theme.text, root.guidesX.includes(modelData) ? 0.8 : 0.07)
                }
            }

            Repeater {
                model: win.linesY

                Rectangle {
                    required property real modelData
                    y: stage.height * modelData
                    width: stage.width
                    height: 1
                    color: Qt.alpha(Theme.text, root.guidesY.includes(modelData) ? 0.8 : 0.07)
                }
            }

            // Edge margins, once caught
            Repeater {
                model: root.guidesX.filter(g => !win.linesX.includes(g))

                Rectangle {
                    required property real modelData
                    x: stage.width * modelData
                    width: 1
                    height: stage.height
                    color: Qt.alpha(Theme.accent, 0.8)
                }
            }

            Repeater {
                model: root.guidesY.filter(g => !win.linesY.includes(g))

                Rectangle {
                    required property real modelData
                    y: stage.height * modelData
                    width: stage.width
                    height: 1
                    color: Qt.alpha(Theme.accent, 0.8)
                }
            }

            Repeater {
                model: Desk.widgets

                Item {
                    id: frame

                    required property var modelData
                    readonly property var rect: Desk.preview?.[modelData.id] ?? modelData
                    readonly property bool picked: Desk.selection.includes(modelData.id)
                    // The one the panel edits; only it has resize handles
                    readonly property bool main: Desk.selected === modelData.id && Desk.selection.length === 1
                    property var start: null

                    // Drag state: corner -1 moves the whole selection, 0..3 resize this one from that corner (tl, tr, bl, br)
                    function begin(mouse, item, corner) {
                        if (corner < 0 && (mouse.modifiers & Qt.ControlModifier)) {
                            Desk.select(modelData.id, true);
                            return;
                        }
                        if (corner >= 0 || !picked)
                            Desk.select(modelData.id);
                        const p = item.mapToItem(stage, mouse.x, mouse.y);
                        const rects = {};
                        for (const w of Desk.widgets)
                            if (corner < 0 ? Desk.selection.includes(w.id) : w.id === modelData.id)
                                rects[w.id] = { x: w.x, y: w.y, w: w.w, h: w.h };
                        start = { px: p.x, py: p.y, x: modelData.x, y: modelData.y, w: modelData.w, h: modelData.h, rects: rects };
                    }

                    function drag(mouse, item, corner) {
                        if (!start)
                            return;
                        const p = item.mapToItem(stage, mouse.x, mouse.y);
                        const dx = (p.x - start.px) / win.sw, dy = (p.y - start.py) / win.sh;
                        const free = mouse.modifiers & Qt.AltModifier;
                        const gx = [], gy = [];
                        let l = start.x - start.w / 2, r = start.x + start.w / 2, t = start.y - start.h / 2, b = start.y + start.h / 2;
                        if (corner < 0) {
                            // The group's bounding box snaps, every member shifts by the same amount
                            const all = Object.values(start.rects);
                            let bl = Math.min(...all.map(o => o.x - o.w / 2)) + dx, br = Math.max(...all.map(o => o.x + o.w / 2)) + dx;
                            let bt = Math.min(...all.map(o => o.y - o.h / 2)) + dy, bb = Math.max(...all.map(o => o.y + o.h / 2)) + dy;
                            let mx = dx, my = dy;
                            if (!free) {
                                mx += win.snapSpan(bl, br, win.sw, gx, win.linesX, 0);
                                my += win.snapSpan(bt, bb, win.sh, gy, win.linesY, win.barTop);
                            }
                            const moved = {};
                            for (const id in start.rects) {
                                const o = start.rects[id];
                                moved[id] = { x: o.x + mx, y: o.y + my, w: o.w, h: o.h };
                            }
                            root.guidesX = gx;
                            root.guidesY = gy;
                            Desk.preview = moved;
                            return;
                        } else {
                            const left = corner === 0 || corner === 2, up = corner < 2;
                            let nx = (left ? l : r) + dx, ny = (up ? t : b) + dy;
                            if (!free) {
                                nx += win.snapSpan(nx, nx, win.sw, gx, win.linesX, 0);
                                ny += win.snapSpan(ny, ny, win.sh, gy, win.linesY, win.barTop);
                            }
                            const minW = 40 / win.sw, minH = 30 / win.sh;
                            if (left) l = Math.min(nx, r - minW); else r = Math.max(nx, l + minW);
                            if (up) t = Math.min(ny, b - minH); else b = Math.max(ny, t + minH);
                            // Shift keeps the proportions, scaling from the opposite corner
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                const k = Math.max((r - l) / start.w, (b - t) / start.h);
                                if (left) l = r - start.w * k; else r = l + start.w * k;
                                if (up) t = b - start.h * k; else b = t + start.h * k;
                                gx.length = gy.length = 0;
                            }
                        }
                        root.guidesX = gx;
                        root.guidesY = gy;
                        Desk.preview = { [modelData.id]: { x: (l + r) / 2, y: (t + b) / 2, w: r - l, h: b - t } };
                    }

                    function end() {
                        // Saving rebuilds the frames, this one included, so everything else goes first
                        const done = start ? Desk.preview : null;
                        const id = modelData.id, wasStarted = !!start;
                        start = null;
                        root.guidesX = [];
                        root.guidesY = [];
                        Desk.preview = null;
                        if (done)
                            Desk.moveWidgets(done);
                        // A plain click inside a group narrows it down to this one
                        else if (wasStarted && Desk.selection.length > 1)
                            Desk.select(id);
                    }

                    x: (rect.x - rect.w / 2) * win.sw
                    y: (rect.y - rect.h / 2) * win.sh
                    width: rect.w * win.sw
                    height: rect.h * win.sh
                    z: picked ? 1 : 0

                    Rectangle {
                        anchors.fill: parent
                        color: frame.picked ? Qt.alpha(Theme.accent, 0.08) : moveArea.containsMouse ? Qt.alpha(Theme.text, 0.05) : "transparent"
                        radius: 6
                        border.width: frame.picked ? 2 : 1
                        border.color: frame.picked ? Theme.accent : Qt.alpha(Theme.text, moveArea.containsMouse ? 0.6 : 0.3)
                    }

                    // Name tag
                    Rectangle {
                        x: 8
                        y: 8
                        width: tagRow.implicitWidth + 16
                        height: 24
                        radius: 12
                        color: frame.picked ? Theme.accent : Qt.alpha(Theme.bg, 0.85)

                        Row {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: 4

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Desk.kinds[frame.modelData.type]?.icon ?? "widgets"
                                font.pixelSize: 15
                                color: frame.picked ? Theme.bg : Theme.text
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 12
                                color: frame.picked ? Theme.bg : Theme.text
                                text: (Desk.kinds[frame.modelData.type]?.name ?? "") + (frame.modelData.style ? " · " + frame.modelData.style : "")
                            }
                        }
                    }

                    MouseArea {
                        id: moveArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => frame.begin(mouse, moveArea, -1)
                        onPositionChanged: mouse => {
                            if (pressed)
                                frame.drag(mouse, moveArea, -1);
                        }
                        onReleased: frame.end()
                        onCanceled: frame.end()
                    }

                    Repeater {
                        model: 4

                        Rectangle {
                            id: handle

                            required property int index
                            readonly property bool atLeft: index === 0 || index === 2
                            readonly property bool atTop: index < 2

                            visible: frame.main
                            x: (atLeft ? 0 : frame.width) - width / 2
                            y: (atTop ? 0 : frame.height) - height / 2
                            width: handleArea.containsMouse || handleArea.pressed ? 18 : 14
                            height: width
                            radius: width / 2
                            color: Theme.bg
                            border.width: 2
                            border.color: Theme.accent

                            MouseArea {
                                id: handleArea

                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: handle.atLeft === handle.atTop ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                                onPressed: mouse => frame.begin(mouse, handleArea, handle.index)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        frame.drag(mouse, handleArea, handle.index);
                                }
                                onReleased: frame.end()
                                onCanceled: frame.end()
                            }
                        }
                    }
                }
            }

            EditorPanel {
                id: panel

                z: 10
                // Keys go back to the editor once a rename is done
                onRenameIdChanged: {
                    if (renameId === "")
                        keys.forceActiveFocus();
                }
                x: root.panelShown ? 16 : -width - 2
                y: 16
                width: 380
                height: parent.height - 32
                Behavior on x { NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }
            }

            // Brings a hidden panel back
            Rectangle {
                z: 10
                x: root.panelShown ? -width : -radius
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 72
                radius: 14
                color: tabArea.containsMouse ? Theme.accent : Qt.alpha(Theme.bg, 0.9)
                border.width: 1
                border.color: Theme.muted
                Behavior on x { NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }

                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 6
                    text: "chevron_right"
                    font.pixelSize: 22
                    color: tabArea.containsMouse ? Theme.bg : Theme.text
                }

                MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.panelShown = true
                }
            }

            Item {
                id: keys

                focus: Desk.editing
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier, sc = event.nativeScanCode;
                    const id = Desk.selected, sel = Desk.selection;
                    // Ctrl+Z (RU "Я") undoes, Ctrl+D (RU "В") duplicates, Ctrl+C/X/V (С/Ч/М) copy, cut and paste,
                    // Ctrl+A (Ф) picks everything; H (RU "Р") hides the panel
                    if (ctrl && (event.key === Qt.Key_Z || sc === 52)) {
                        Desk.undo();
                    } else if (ctrl && (event.key === Qt.Key_D || sc === 40)) {
                        if (sel.length) {
                            Desk.copyWidgets(sel);
                            Desk.pasteWidgets();
                        }
                    } else if (ctrl && (event.key === Qt.Key_C || sc === 54)) {
                        if (sel.length)
                            Desk.copyWidgets(sel);
                    } else if (ctrl && (event.key === Qt.Key_X || sc === 53)) {
                        if (sel.length) {
                            Desk.copyWidgets(sel);
                            Desk.removeWidgets(sel);
                        }
                    } else if (ctrl && (event.key === Qt.Key_V || sc === 55)) {
                        Desk.pasteWidgets();
                    } else if (ctrl && (event.key === Qt.Key_A || sc === 38)) {
                        Desk.selectMany(Desk.widgets.map(w => w.id));
                    } else if (event.key === Qt.Key_F2) {
                        if (Desk.currentId) {
                            panel.menu = true;
                            panel.renameId = Desk.currentId;
                        }
                    } else if (!ctrl && (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight || sc === 34 || sc === 35)) {
                        // [ and ] (RU Х and Ъ) step through wallpapers
                        Quickshell.execDetached(["qs", "ipc", "call", "wallpaper", event.key === Qt.Key_BracketLeft || sc === 34 ? "prev" : "next"]);
                    } else if (!ctrl && (event.key === Qt.Key_H || sc === 43)) {
                        root.panelShown = !root.panelShown;
                    } else if (event.key === Qt.Key_Escape) {
                        if (id)
                            Desk.select("");
                        else
                            Desk.editing = false;
                    } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                        if (sel.length)
                            Desk.removeWidgets(sel);
                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        const all = Desk.widgets, i = all.findIndex(x => x.id === id);
                        if (all.length)
                            Desk.select(all[(i + (event.key === Qt.Key_Tab ? 1 : all.length - 1) + (i < 0 ? 1 : 0)) % all.length].id);
                    } else if (sel.length && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
                        const px = event.modifiers & Qt.ShiftModifier ? 10 : 1;
                        const dx = event.key === Qt.Key_Left ? -px : event.key === Qt.Key_Right ? px : 0;
                        const dy = event.key === Qt.Key_Up ? -px : event.key === Qt.Key_Down ? px : 0;
                        const rects = {};
                        for (const w of Desk.widgets)
                            if (sel.includes(w.id))
                                rects[w.id] = { x: w.x + dx / win.sw, y: w.y + dy / win.sh };
                        Desk.moveWidgets(rects);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }
        }
    }
}
