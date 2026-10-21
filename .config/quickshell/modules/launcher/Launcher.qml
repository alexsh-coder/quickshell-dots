import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    property bool open: false
    // Flipped off and on in show() to replay the rows' entrance
    property bool populated: true
    // True right after opening: rows pop in like bubbles instead of sliding
    property bool entering: false
    // Hover only takes over the selection after a real cursor move, not when the list scrolls under it
    property bool mouseActive: false
    property point lastCursor: Qt.point(-1, -1)
    property string query: ""
    // Snapshot taken on open, so the list doesn't reshuffle while the card fades out after a launch
    property var ranks: ({})

    readonly property int rowHeight: 52
    readonly property int maxRows: 7

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const alt = swapLayout(q);
        const used = a => ranks[a.id] ?? 0;
        // QML's sort() isn't stable, so name is an explicit last tie-breaker
        const byName = (x, y) => x.name.localeCompare(y.name);
        if (!q) {
            const pinned = Pins.ids.map(id => apps.find(a => a.id === id)).filter(a => a);
            const rest = apps.filter(a => !Pins.ids.includes(a.id));
            return pinned.concat(rest.sort((x, y) => used(y) - used(x) || byName(x, y)));
        }
        return apps
            .map(a => ({ a, s: Math.max(score(a, q), alt === q ? 0 : score(a, alt) - 5) }))
            .filter(r => r.s > 0)
            .sort((x, y) => y.s - x.s || used(y.a) - used(x.a) || byName(x.a, y.a))
            .map(r => r.a);
    }

    readonly property string ruKeys: "йцукенгшщзхъфывапролджэячсмитьбю"
    readonly property string enKeys: "qwertyuiop[]asdfghjkl;'zxcvbnm,."

    // Typing "ашкуащч" on the RU layout still finds "firefox"
    function swapLayout(q) {
        return [...q].map(c => {
            const i = ruKeys.indexOf(c);
            return i < 0 ? c : enKeys[i];
        }).join("");
    }

    function score(a, q) {
        const name = a.name.toLowerCase();
        if (name === q)
            return 100;
        if (name.startsWith(q))
            return 90;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 80;
        if (name.includes(q))
            return 70;
        const extra = [a.genericName, a.id, a.keywords.join(" ")].join(" ").toLowerCase();
        if (extra.includes(q))
            return 50;
        // Fuzzy: every char of q in order, fewer gaps is better
        let pos = -1, gaps = 0;
        for (const c of q) {
            const next = name.indexOf(c, pos + 1);
            if (next < 0)
                return 0;
            if (pos >= 0)
                gaps += next - pos - 1;
            pos = next;
        }
        return Math.max(1, 40 - gaps);
    }

    function show() {
        // Everything here runs before open flips, so geometry snaps instead of animating
        search.clear();
        query = "";
        mouseActive = false;
        lastCursor = Qt.point(-1, -1);
        ranks = Usage.ranks();
        entering = true;
        enterTimer.restart();
        populated = false;
        populated = true;
        resultsView.currentIndex = 0;
        resultsView.positionViewAtBeginning();
        open = true;
        Qt.callLater(() => search.forceActiveFocus());
    }

    function cursorMoved(item, x, y) {
        const p = item.mapToGlobal(x, y);
        if (p.x === lastCursor.x && p.y === lastCursor.y)
            return false;
        const first = lastCursor.x < 0;
        lastCursor = p;
        if (!first)
            mouseActive = true;
        return mouseActive;
    }

    function hide() {
        open = false;
    }

    function launch(entry) {
        if (!entry)
            return;
        Usage.record(entry.id);
        if (entry.runInTerminal)
            Quickshell.execDetached([Theme.terminal, "-e"].concat(Array.from(entry.command)));
        else
            entry.execute();
        hide();
    }

    function togglePin(entry) {
        if (!entry)
            return;
        const ids = Pins.ids.slice();
        const i = ids.indexOf(entry.id);
        if (i >= 0)
            ids.splice(i, 1);
        else
            ids.push(entry.id);
        Pins.save(ids);
    }

    // Pins sit on top of the empty-query list in their saved order
    function movePin(entry, step) {
        const ids = Pins.ids.slice();
        const i = ids.indexOf(entry?.id);
        const j = i + step;
        if (query.trim() || i < 0 || j < 0 || j >= ids.length)
            return;
        ids.splice(j, 0, ids.splice(i, 1)[0]);
        Pins.save(ids);
        resultsView.currentIndex = j;
    }

    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        // P on any layout: Qt reports the RU layout's "З" as a different key, the scancode is the same
        const isP = event.key === Qt.Key_P || event.nativeScanCode === 33;

        if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Tab].includes(event.key))
            mouseActive = false;

        if (event.key === Qt.Key_Escape) {
            hide();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            launch(resultsView.currentItem?.modelData ?? null);
        } else if (ctrl && isP) {
            togglePin(resultsView.currentItem?.modelData ?? null);
        } else if (ctrl && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            movePin(resultsView.currentItem?.modelData, event.key === Qt.Key_Up ? -1 : 1);
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            resultsView.incrementCurrentIndex();
        } else if (event.key === Qt.Key_Up) {
            resultsView.decrementCurrentIndex();
        } else {
            return;
        }
        event.accepted = true;
    }

    Timer {
        id: enterTimer
        interval: 900
        onTriggered: root.entering = false
    }

    // Usage may finish loading after the first open
    Connections {
        target: Usage
        function onAppsChanged() {
            if (root.open)
                root.ranks = Usage.ranks();
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }

        function open(): void { root.show(); }
        function close(): void { root.hide(); }
    }

    PanelWindow {
        visible: root.open || card.opacity > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.open ? 0.3 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: card

            x: (parent.width - width) / 2
            y: parent.height * 0.2
            width: 560
            height: content.implicitHeight + 24
            radius: Theme.radius + 6
            color: Qt.alpha(Theme.bg, 0.85)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.25)

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: root.open ? Easing.OutBack : Easing.InCubic } }
            Behavior on height {
                enabled: root.open
                NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
            }

            // Swallow clicks so they don't reach the close-on-outside-click area
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: content
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.6) : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Theme.anim } }

                    Icon {
                        id: searchIcon
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        font.pixelSize: 22
                        color: Theme.accent
                    }

                    TextInput {
                        id: search

                        anchors.left: searchIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font
                        font.pixelSize: 17
                        color: Theme.text
                        selectionColor: Qt.alpha(Theme.accent, 0.4)
                        clip: true
                        focus: true
                        onTextEdited: {
                            root.entering = false;
                            root.query = text;
                            resultsView.currentIndex = 0;
                        }
                        Keys.onPressed: event => root.handleKey(event)

                        Label {
                            visible: !search.text
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 17
                            color: Theme.subtext
                            text: "Search apps"
                        }
                    }
                }

                ListView {
                    id: resultsView

                    width: parent.width
                    height: Math.min(count, root.maxRows) * root.rowHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 160
                    highlightMoveVelocity: -1
                    currentIndex: 0

                    model: ScriptModel {
                        values: root.populated ? root.results : []
                    }

                    highlight: Rectangle {
                        radius: Theme.radius
                        color: Qt.alpha(Theme.accent, 0.14)
                    }

                    delegate: ResultRow {
                        launcher: root
                        height: root.rowHeight
                        width: resultsView.width
                        pinned: Pins.ids.includes(modelData.id)
                        current: ListView.isCurrentItem
                    }

                    add: Transition {
                        id: addTrans
                        SequentialAnimation {
                            PropertyAction { property: "opacity"; value: 0 }
                            PropertyAction { property: "scale"; value: root.entering ? 0.86 : 1 }
                            PropertyAction { property: "lift"; value: root.entering ? 14 : 0 }
                            PauseAnimation { duration: Math.max(0, Math.min(addTrans.ViewTransition.index, 10)) * (root.entering ? 45 : 18) }
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim }
                                NumberAnimation { property: "x"; from: root.entering ? 0 : 16; to: 0; duration: Theme.anim; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                NumberAnimation { property: "lift"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                            }
                        }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 120 }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: Theme.anim; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim }
                        // An interrupted pop must still settle
                        NumberAnimation { property: "scale"; to: 1; duration: Theme.anim; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "lift"; to: 0; duration: Theme.anim; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
