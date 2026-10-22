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
    // Hidden apps stay out of the list until this is flipped for the current session
    property bool showHidden: false
    // Snapshot taken on open, so the list doesn't reshuffle while the card fades out after a launch
    property var ranks: ({})
    // Pin being dragged: its index, where its row's top is and the slot it would drop into.
    // The model keeps its order until the drop, the other pins only shift visually.
    property string dragId: ""
    property int dragFrom: -1
    property real dragTop: 0
    readonly property int dragSlot: Math.round(dragTop / rowHeight)
    // True for the instant the drop reorders the model, so nothing animates the jump
    property bool dropping: false
    // Context menu: the app it's for and its actions, both kept while it fades out
    property bool menuOpen: false
    property var menuEntry: null
    property var menuItems: []
    // Id of the app whose name is being edited in its row, and the text typed so far
    property string renaming: ""
    property string renameText: ""

    readonly property int rowHeight: 52
    readonly property int maxRows: 7

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay && (showHidden || !Hidden.ids.includes(a.id)))
        .sort((a, b) => Names.name(a).localeCompare(Names.name(b)))

    // Pins of apps that are still installed; the others keep their place in the file but are skipped
    readonly property var shownPins: Pins.ids.filter(id => apps.some(a => a.id === id))

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const alt = swapLayout(q);
        const used = a => ranks[a.id] ?? 0;
        // QML's sort() isn't stable, so name is an explicit last tie-breaker
        const byName = (x, y) => Names.name(x).localeCompare(Names.name(y));
        if (!q) {
            const pinned = shownPins.map(id => apps.find(a => a.id === id));
            const rest = apps.filter(a => !shownPins.includes(a.id));
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
        const name = Names.name(a).toLowerCase();
        if (name === q)
            return 100;
        if (name.startsWith(q))
            return 90;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 80;
        if (name.includes(q))
            return 70;
        // The original name still finds a renamed app
        const extra = [a.name, a.genericName, a.id, a.keywords.join(" ")].join(" ").toLowerCase();
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
        showHidden = false;
        menuOpen = false;
        renaming = "";
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
        closeMenu();
        commitRename();
        endDrag();
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

    function toggleHidden(entry) {
        if (!entry)
            return;
        const ids = Hidden.ids.slice();
        const i = ids.indexOf(entry.id);
        if (i >= 0)
            ids.splice(i, 1);
        else
            ids.push(entry.id);
        Hidden.save(ids);
    }

    // Keeps the selection on an app after a change reorders the list
    function select(id) {
        Qt.callLater(() => {
            const i = results.findIndex(a => a.id === id);
            if (i >= 0)
                resultsView.currentIndex = i;
        });
    }

    function startRename(entry) {
        if (!entry)
            return;
        select(entry.id);
        renameText = Names.name(entry);
        renaming = entry.id;
    }

    // An empty name or the original one drops the override
    function commitRename() {
        if (!renaming)
            return;
        const id = renaming;
        renaming = "";
        const text = renameText.trim();
        const entry = DesktopEntries.applications.values.find(a => a.id === id);
        Names.rename(id, text === entry?.name ? "" : text);
        select(id);
        search.forceActiveFocus();
    }

    function cancelRename() {
        renaming = "";
        search.forceActiveFocus();
    }

    // pos: where the click was, in window coordinates; without it the menu drops from the selected row
    function openMenu(entry, pos) {
        if (!entry)
            return;
        commitRename();
        const pinned = Pins.ids.includes(entry.id);
        const hidden = Hidden.ids.includes(entry.id);
        const items = [
            { action: "pin", icon: "push_pin", text: pinned ? "Unpin" : "Pin", hint: "Ctrl P" },
            { action: "dock", icon: "dock_to_bottom", text: DockPins.has(entry.id) ? "Unpin from dock" : "Pin to dock", hint: "" },
            { action: "rename", icon: "edit", text: "Rename", hint: "F2" }
        ];
        if (Names.names[entry.id] !== undefined)
            items.push({ action: "reset", icon: "undo", text: "Reset name", hint: "" });
        items.push({ action: "hide", icon: hidden ? "visibility" : "visibility_off", text: hidden ? "Unhide" : "Hide", hint: "Ctrl H" });
        menuEntry = entry;
        menuItems = items;
        menu.current = pos ? -1 : 0;

        const row = resultsView.currentItem;
        const p = pos ?? (row ? row.mapToItem(null, row.width - menu.width - 8, row.height - 4) : Qt.point(0, 0));
        const win = menu.parent;
        menu.flipped = p.y + menu.height > win.height - 8;
        menu.x = Math.max(8, Math.min(p.x, win.width - menu.width - 8));
        menu.y = menu.flipped ? p.y - menu.height : p.y;
        menuOpen = true;
    }

    function closeMenu() {
        menuOpen = false;
    }

    function runMenu(action) {
        const entry = menuEntry;
        closeMenu();
        if (action === "pin")
            togglePin(entry);
        else if (action === "dock")
            DockPins.toggle(entry.id);
        else if (action === "rename")
            startRename(entry);
        else if (action === "reset") {
            Names.rename(entry.id, "");
            select(entry.id);
        } else if (action === "hide")
            toggleHidden(entry);
    }

    function menuKey(event) {
        const n = menuItems.length;
        if (event.key === Qt.Key_Escape)
            closeMenu();
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
            menu.current = (menu.current + 1) % n;
        else if (event.key === Qt.Key_Up)
            menu.current = (Math.max(menu.current, 0) - 1 + n) % n;
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && menu.current >= 0)
            runMenu(menuItems[menu.current].action);
        else if (event.key === Qt.Key_Menu)
            closeMenu();
        // Everything else is swallowed so it doesn't reach the search field
        event.accepted = true;
    }

    function savePinOrder(ids) {
        Pins.save(ids.concat(Pins.ids.filter(id => !shownPins.includes(id))));
    }

    // Pins sit on top of the empty-query list in their saved order
    function movePin(entry, step) {
        const ids = shownPins.slice();
        const i = ids.indexOf(entry?.id);
        const j = i + step;
        if (query.trim() || i < 0 || j < 0 || j >= ids.length)
            return;
        ids.splice(j, 0, ids.splice(i, 1)[0]);
        savePinOrder(ids);
        resultsView.currentIndex = j;
    }

    function startDrag(entry, index) {
        if (query.trim() || shownPins.indexOf(entry.id) !== index)
            return false;
        dragId = entry.id;
        dragFrom = index;
        return true;
    }

    // top: where the dragged row's top would be, in list content coordinates
    function dragTo(top) {
        dragTop = Math.max(0, Math.min(top, (shownPins.length - 1) * rowHeight));
        resultsView.currentIndex = dragSlot;
    }

    // How far a row steps aside to open the slot the dragged pin hovers over
    function dragShift(index) {
        if (!dragId || index === dragFrom)
            return 0;
        if (dragFrom < index && index <= dragSlot)
            return -rowHeight;
        if (dragSlot <= index && index < dragFrom)
            return rowHeight;
        return 0;
    }

    function endDrag() {
        if (!dragId)
            return;
        const ids = shownPins.slice();
        const slot = dragSlot;
        ids.splice(slot, 0, ids.splice(dragFrom, 1)[0]);
        dropping = true;
        savePinOrder(ids);
        resultsView.forceLayout();
        dragId = "";
        dragFrom = -1;
        resultsView.currentIndex = slot;
        dropping = false;
    }

    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        // P on any layout: Qt reports the RU layout's "З" as a different key, the scancode is the same
        const isP = event.key === Qt.Key_P || event.nativeScanCode === 33;
        const isH = event.key === Qt.Key_H || event.nativeScanCode === 43;
        const shift = event.modifiers & Qt.ShiftModifier;

        if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Tab].includes(event.key))
            mouseActive = false;

        if (menuOpen) {
            menuKey(event);
            return;
        }

        if (event.key === Qt.Key_Escape) {
            hide();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            launch(resultsView.currentItem?.modelData ?? null);
        } else if (event.key === Qt.Key_Menu || shift && event.key === Qt.Key_F10) {
            openMenu(resultsView.currentItem?.modelData ?? null);
        } else if (event.key === Qt.Key_F2) {
            startRename(resultsView.currentItem?.modelData ?? null);
        } else if (ctrl && isP) {
            togglePin(resultsView.currentItem?.modelData ?? null);
        } else if (ctrl && shift && isH) {
            showHidden = !showHidden;
        } else if (ctrl && isH) {
            toggleHidden(resultsView.currentItem?.modelData ?? null);
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
            // Centered as if the list were full, so the search field stays put while results come and go
            y: (parent.height - (24 + 48 + 8 + root.maxRows * root.rowHeight)) / 2
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
                onPressed: root.commitRename()
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
                        anchors.right: hiddenMark.left
                        anchors.rightMargin: 10
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

                    // Marks that hidden apps are listed too
                    Icon {
                        id: hiddenMark
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "visibility"
                        font.pixelSize: 20
                        color: Theme.accent
                        width: root.showHidden ? implicitWidth : 0
                        opacity: root.showHidden ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }
                }

                ListView {
                    id: resultsView

                    width: parent.width
                    height: Math.min(count, root.maxRows) * root.rowHeight
                    clip: true
                    interactive: !root.dragId
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
                        pinned: Pins.ids.includes(modelData?.id)
                        hidden: Hidden.ids.includes(modelData?.id)
                        current: ListView.isCurrentItem
                    }

                    add: Transition {
                        id: addTrans
                        SequentialAnimation {
                            PropertyAction { property: "opacity"; value: 0 }
                            PropertyAction { property: "scale"; value: root.entering ? 1 - 0.14 * Math.pow(0.72, addTrans.ViewTransition.index) : 1 }
                            PropertyAction { property: "lift"; value: root.entering ? 14 * Math.pow(0.72, addTrans.ViewTransition.index) : 0 }
                            PauseAnimation { duration: Math.max(0, Math.min(addTrans.ViewTransition.index, 10)) * (root.entering ? 45 : 18) }
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim }
                                NumberAnimation { property: "x"; from: root.entering ? 0 : 16; to: 0; duration: Theme.anim; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.5 + 2.1 * Math.pow(0.72, addTrans.ViewTransition.index) }
                                NumberAnimation { property: "lift"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.5 + 2.1 * Math.pow(0.72, addTrans.ViewTransition.index) }
                            }
                        }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 120 }
                    }
                    displaced: Transition {
                        enabled: !root.dropping
                        NumberAnimation { properties: "x,y"; duration: Theme.anim; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim }
                        // An interrupted pop must still settle
                        NumberAnimation { property: "scale"; to: 1; duration: Theme.anim; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "lift"; to: 0; duration: Theme.anim; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        // Any click outside the open menu just closes it
        MouseArea {
            anchors.fill: parent
            visible: root.menuOpen
            acceptedButtons: Qt.AllButtons
            onPressed: root.closeMenu()
            onWheel: root.closeMenu()
        }

        ContextMenu {
            id: menu
            open: root.menuOpen
            items: root.menuItems
            onTriggered: action => root.runMenu(action)
        }
    }
}
