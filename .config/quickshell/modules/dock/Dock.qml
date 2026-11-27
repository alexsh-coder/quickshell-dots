import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services
import qs.modules.launcher

// Hidden dock: touching the bottom edge under it peeks a tab, hovering the tab slides the dock up
PanelWindow {
    id: root

    readonly property var apps: DockPins.ids
        .map(id => DesktopEntries.applications.values.find(a => a.id === id))
        .filter(a => a)

    readonly property int size: 36
    readonly property int zoom: 47
    readonly property int gap: 8
    readonly property int edge: 9

    property bool shown: false
    property bool peek: false
    // App the context menu is for, kept while the menu fades out
    property bool menuOpen: false
    property var menuEntry: null
    // Icon being dragged, how far it moved and the slot it would drop into
    property int dragFrom: -1
    property real dragDx: 0
    // The released icon glides into its slot before the order is saved
    property bool settling: false
    readonly property int step: size + gap
    readonly property int dragTo: Math.max(0, Math.min(apps.length - 1, Math.round(dragFrom + dragDx / step)))
    readonly property int baseWidth: apps.length * size + (apps.length - 1) * gap
    property real px: 0
    // Zoom lets go while dragging, so every slot is one step wide
    property real zoomIn: shown && hover.hovered && dragFrom < 0 ? 1 : 0
    Behavior on zoomIn { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    // macOS-style wave measured on the resting layout, so growing icons never move the points they are measured from
    function sizeAt(i) {
        const reach = 1.6 * size;
        const center = (width - apps.length * (size + gap)) / 2 + (i + 0.5) * (size + gap);
        const d = Math.min(1, Math.abs(px - center) / reach);
        return size + (zoom - size) * zoomIn * Math.max(0, Math.cos(d * Math.PI / 2));
    }

    // The pill rises with the largest icon so outline icons never hang over the wallpaper
    readonly property real peak: Math.max(size, ...apps.map((_, i) => sizeAt(i)))

    WlrLayershell.namespace: "dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    // Fixed size: a resizing layer surface gets animated by Hyprland
    implicitHeight: zoom + 2 * edge + 24
    color: "transparent"
    mask: Region { item: root.shown ? area : root.peek ? near : trigger }

    // Window classes don't always match the desktop id (Spotify) or StartupWMClass (Telegram)
    function windowsOf(entry) {
        const ids = [entry.id, entry.startupClass].map(c => c.toLowerCase());
        return ToplevelManager.toplevels.values.filter(t => ids.includes(t.appId.toLowerCase()));
    }

    function open(entry) {
        const wins = windowsOf(entry);
        if (wins.length === 0) {
            if (entry.runInTerminal)
                Quickshell.execDetached([Theme.terminal, "-e"].concat(Array.from(entry.command)));
            else
                entry.execute();
            return;
        }
        // Cycle through the app's windows when one of them is already focused
        const i = wins.findIndex(t => t.activated);
        wins[(i + 1) % wins.length].activate();
    }

    Item {
        id: trigger
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.baseWidth + 2 * root.edge + 2 * 20
        height: 2
    }

    // Pointer can wander around the tab without it dropping back
    Item {
        id: near
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: trigger.width
        height: tab.height + 20
    }

    Item {
        id: area
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: pill.width + 40
        height: parent.height
    }

    HoverHandler {
        id: hover
        onPointChanged: root.px = point.position.x
        onHoveredChanged: {
            if (hovered) {
                hideDelay.stop();
                root.peek = true;
            } else {
                hideDelay.restart();
            }
        }
    }

    Timer {
        id: hideDelay
        interval: 350
        onTriggered: {
            root.shown = root.menuOpen || root.dragFrom >= 0;
            root.peek = false;
        }
    }

    function release() {
        settling = true;
        settle.to = (dragTo - dragFrom) * step;
        settle.restart();
    }

    NumberAnimation {
        id: settle
        target: root
        property: "dragDx"
        duration: Theme.anim
        easing.type: Easing.OutCubic
        onFinished: root.drop()
    }

    // Unpinned ids keep their place at the end of the file
    function drop() {
        settling = false;
        const from = dragFrom, to = dragTo;
        // Reset before saving, so the rebuilt icons don't start shifted and slide back
        dragFrom = -1;
        dragDx = 0;
        if (from >= 0 && to !== from) {
            const ids = apps.map(a => a.id);
            ids.splice(to, 0, ids.splice(from, 1)[0]);
            DockPins.save(ids.concat(DockPins.ids.filter(id => !ids.includes(id))));
        }
        if (!hover.hovered)
            hideDelay.restart();
    }

    // How far an icon steps aside to open the slot the dragged one hovers over
    function shiftOf(i) {
        if (dragFrom < 0 || i === dragFrom)
            return 0;
        if (dragFrom < i && i <= dragTo)
            return -step;
        if (dragTo <= i && i < dragFrom)
            return step;
        return 0;
    }

    function closeMenu() {
        menuOpen = false;
        if (!hover.hovered)
            hideDelay.restart();
    }

    HyprlandFocusGrab {
        windows: [root, menuWindow]
        active: root.menuOpen
        onCleared: root.closeMenu()
    }

    PopupWindow {
        id: menuWindow

        property Item slot: null

        visible: root.menuOpen || menu.opacity > 0
        anchor.item: slot
        anchor.rect.x: slot ? slot.width / 2 : 0
        anchor.rect.y: -root.edge - 6
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: menu.width
        implicitHeight: menu.height
        color: "transparent"

        ContextMenu {
            id: menu
            open: root.menuOpen
            flipped: true
            items: [{ action: "unpin", icon: "keep_off", text: "Unpin from dock", hint: "" }]
            onTriggered: {
                DockPins.toggle(root.menuEntry.id);
                root.closeMenu();
            }
        }
    }

    Rectangle {
        id: tab

        readonly property bool out: root.peek && !root.shown

        width: 56
        height: 10 + radius
        radius: 7
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -radius
        color: Qt.alpha(Theme.bg, 0.85)
        border.width: 1
        border.color: Qt.alpha(Theme.muted, 0.6)
        opacity: out ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        transform: Translate {
            y: tab.out ? 0 : tab.height - tab.radius
            Behavior on y { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            width: 20
            height: 3
            radius: 1.5
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - parent.radius - height) / 2 + 1
            color: Theme.accent
        }

        // The edge row is left out, or the tab would open the dock right under a pointer resting there
        HoverHandler {
            onPointChanged: {
                if (hovered && root.peek && point.position.y < tab.height - tab.radius - 3)
                    root.shown = true;
            }
        }
    }

    Rectangle {
        id: pill

        width: row.implicitWidth + 2 * root.edge - root.gap
        height: root.peak + 2 * root.edge
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.edge
        radius: Theme.radius + 6
        color: Qt.alpha(Theme.bg, 0.85)
        border.width: 1
        border.color: Qt.alpha(Theme.muted, 0.6)

        // Slide via a transform, so height changes don't restart the reveal animation
        transform: Translate {
            y: root.shown ? 0 : pill.height + root.edge + 4

            Behavior on y {
                NumberAnimation {
                    duration: root.shown ? Theme.animSpatial : Theme.anim
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.shown ? Theme.spatial : Theme.emphasizedAccel
                }
            }
        }

        Row {
            id: row
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.edge
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: root.apps

                Item {
                    id: slot
                    required property var modelData
                    required property int index

                    readonly property real s: root.sizeAt(index)
                    readonly property bool dragged: root.dragFrom === index

                    // Slots carry the gap themselves so the pointer never falls between icons;
                    // every slot is as tall as the pill, so icons share one centre line
                    width: s + root.gap
                    height: root.peak
                    z: dragged ? 1 : 0

                    transform: Translate {
                        x: slot.dragged ? root.dragDx : root.shiftOf(slot.index)
                        Behavior on x {
                            enabled: !slot.dragged
                            NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
                        }
                    }

                    AppIcon {
                        anchors.centerIn: parent
                        width: slot.s
                        height: slot.s
                        icon: slot.modelData.icon
                        scale: slot.dragged && !root.settling ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                    }

                    DragHandler {
                        target: null
                        enabled: !root.settling
                        yAxis.enabled: false
                        onActiveChanged: {
                            if (active)
                                root.dragFrom = slot.index;
                            else
                                root.release();
                        }
                        onTranslationChanged: {
                            if (active)
                                root.dragDx = Math.max(-slot.index * root.step, Math.min(translation.x, (root.apps.length - 1 - slot.index) * root.step));
                        }
                    }

                    TapHandler {
                        onTapped: {
                            Sfx.tap("click");
                            root.open(slot.modelData);
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: {
                            Sfx.tap("click");
                            menu.current = -1;
                            menuWindow.slot = slot;
                            root.menuEntry = slot.modelData;
                            root.menuOpen = true;
                        }
                    }
                }
            }
        }
    }
}
