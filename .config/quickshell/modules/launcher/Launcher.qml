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
    property string zone: "list"
    property string flyId: ""
    // Snapshot taken on open, so the list doesn't reshuffle while the card fades out after a launch
    property var ranks: ({})

    readonly property int pinSize: 56
    readonly property int pinGap: 6
    readonly property int rowHeight: 52
    readonly property int maxRows: 7

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const alt = swapLayout(q);
        const used = a => ranks[a.id] ?? 0;
        // apps is already sorted by name, and sort() is stable, so name stays the last tie-breaker
        return apps
            .map(a => ({ a, s: q ? Math.max(score(a, q), alt === q ? 0 : score(a, alt) - 5) : 1 }))
            .filter(r => r.s > 0)
            .sort((x, y) => y.s - x.s || used(y.a) - used(x.a))
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
        zone = "list";
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

    function pinIndex(id) {
        for (let i = 0; i < pinModel.count; i++) {
            if (pinModel.get(i).appId === id)
                return i;
        }
        return -1;
    }

    function savePins() {
        const ids = [];
        for (let i = 0; i < pinModel.count; i++)
            ids.push(pinModel.get(i).appId);
        Pins.save(ids);
    }

    function loadPins() {
        const ids = Pins.ids.filter(id => DesktopEntries.byId(id));
        let same = ids.length === pinModel.count;
        for (let i = 0; same && i < ids.length; i++)
            same = pinModel.get(i).appId === ids[i];
        if (same)
            return;
        pinModel.clear();
        for (const id of ids)
            pinModel.append({ appId: id });
    }

    function togglePin(entry, from) {
        if (!entry)
            return;
        const i = pinIndex(entry.id);
        if (i >= 0) {
            pinModel.remove(i);
            pinsView.currentIndex = Math.min(pinsView.currentIndex, pinModel.count - 1);
            if (pinModel.count === 0)
                zone = "list";
        } else {
            if (from)
                ghost.fly(entry, from);
            pinModel.append({ appId: entry.id });
        }
        savePins();
    }

    function movePin(from, to) {
        if (from === to || to < 0 || to >= pinModel.count)
            return;
        pinModel.move(from, to, 1);
        pinsView.currentIndex = to;
    }

    function currentEntry() {
        return zone === "pins"
            ? DesktopEntries.byId(pinModel.get(pinsView.currentIndex)?.appId ?? "")
            : resultsView.currentItem?.modelData ?? null;
    }

    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        // P on any layout: Qt reports the RU layout's "З" as a different key, the scancode is the same
        const isP = event.key === Qt.Key_P || event.nativeScanCode === 33;

        if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_Tab].includes(event.key))
            mouseActive = false;

        if (event.key === Qt.Key_Escape) {
            hide();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            launch(currentEntry());
        } else if (ctrl && isP) {
            const entry = currentEntry();
            togglePin(entry, zone === "list" ? resultsView.currentItem?.iconItem : null);
        } else if (event.key === Qt.Key_Tab) {
            zone = zone === "list" && pinModel.count > 0 ? "pins" : "list";
        } else if (event.key === Qt.Key_Down) {
            if (zone === "pins")
                zone = "list";
            else
                resultsView.incrementCurrentIndex();
        } else if (event.key === Qt.Key_Up) {
            if (zone === "list" && resultsView.currentIndex <= 0 && pinModel.count > 0)
                zone = "pins";
            else if (zone === "list")
                resultsView.decrementCurrentIndex();
        } else if (zone === "pins" && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            const step = event.key === Qt.Key_Left ? -1 : 1;
            if (ctrl) {
                movePin(pinsView.currentIndex, pinsView.currentIndex + step);
                savePins();
            } else {
                pinsView.currentIndex = Math.max(0, Math.min(pinModel.count - 1, pinsView.currentIndex + step));
            }
        } else {
            return;
        }
        event.accepted = true;
    }

    ListModel {
        id: pinModel
    }

    Timer {
        id: enterTimer
        interval: 900
        onTriggered: root.entering = false
    }

    Connections {
        target: Pins
        function onIdsChanged() { root.loadPins(); }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.loadPins(); }
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

                Item {
                    width: parent.width
                    height: pinModel.count > 0 ? root.pinSize + 8 : 0
                    clip: !pinsView.dragging
                    Behavior on height { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

                    ListView {
                        id: pinsView

                        property bool dragging: false
                        property string hoveredName: ""

                        x: (parent.width - width) / 2
                        y: 4
                        width: Math.max(0, pinModel.count * (root.pinSize + root.pinGap) - root.pinGap)
                        height: root.pinSize
                        orientation: ListView.Horizontal
                        spacing: root.pinGap
                        interactive: false
                        model: pinModel
                        Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

                        delegate: PinTile {
                            launcher: root
                            size: root.pinSize
                            selected: root.zone === "pins" && ListView.isCurrentItem
                        }

                        add: Transition {
                            NumberAnimation { property: "scale"; from: 0; to: 1; duration: Theme.anim + 80; easing.type: Easing.OutBack }
                        }
                        remove: Transition {
                            NumberAnimation { properties: "scale,opacity"; to: 0; duration: Theme.anim; easing.type: Easing.InCubic }
                        }
                        move: Transition {
                            NumberAnimation { property: "x"; duration: Theme.anim; easing.type: Easing.OutCubic }
                        }
                        displaced: Transition {
                            NumberAnimation { property: "x"; duration: Theme.anim; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: 1
                    border.color: search.activeFocus && root.zone === "list" ? Qt.alpha(Theme.accent, 0.6) : "transparent"
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
                            root.zone = "list";
                            resultsView.currentIndex = 0;
                        }
                        Keys.onPressed: event => root.handleKey(event)

                        Label {
                            visible: !search.text
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 17
                            color: Theme.subtext
                            // Pins are icon-only, so their name shows up here
                            readonly property string hovered: root.mouseActive ? pinsView.hoveredName : ""
                            text: root.zone === "pins" || hovered
                                  ? (hovered || root.currentEntry()?.name || "")
                                  : "Search apps"
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
                        opacity: root.zone === "list" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }

                    delegate: ResultRow {
                        launcher: root
                        height: root.rowHeight
                        width: resultsView.width
                        pinned: Pins.ids.includes(modelData.id)
                        current: root.zone === "list" && ListView.isCurrentItem
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

            IconImage {
                id: ghost

                property string target: ""

                function fly(entry, from) {
                    const p = from.mapToItem(card, 0, 0);
                    source = Quickshell.iconPath(entry.icon, "application-x-executable");
                    x = p.x;
                    y = p.y;
                    implicitSize = from.width;
                    // The new pin lands last; the row re-centers around it
                    const n = pinModel.count + 1;
                    const rowWidth = n * (root.pinSize + root.pinGap) - root.pinGap;
                    const icon = Math.round(root.pinSize * 0.64);
                    flyX.to = content.x + (content.width + rowWidth) / 2 - (root.pinSize + icon) / 2;
                    flyY.to = content.y + 4 + (root.pinSize - icon) / 2;
                    flySize.to = icon;
                    root.flyId = entry.id;
                    flight.restart();
                }

                visible: flight.running
                z: 10

                ParallelAnimation {
                    id: flight
                    NumberAnimation { id: flyX; target: ghost; property: "x"; duration: 460; easing.type: Easing.InOutCubic }
                    NumberAnimation { id: flyY; target: ghost; property: "y"; duration: 460; easing.type: Easing.InOutBack; easing.overshoot: 2.2 }
                    NumberAnimation { id: flySize; target: ghost; property: "implicitSize"; duration: 460; easing.type: Easing.InOutCubic }
                    onFinished: root.flyId = ""
                }
            }
        }
    }
}
