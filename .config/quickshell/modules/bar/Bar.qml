import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services
import qs.modules.bar.popouts

// Taller than the bar so popouts can grow out of it; input passes through
// everywhere except the bar and the open panel
PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight + 600
    exclusiveZone: Theme.barHeight
    color: "transparent"

    WlrLayershell.namespace: "qs-bar"
    WlrLayershell.keyboardFocus: popouts.pinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: bar
        Region { item: popouts.hitbox }
    }

    readonly property var triggers: [
        { name: "keyboard", item: kb },
        { name: "network", item: network },
        { name: "vpn", item: vpn },
        { name: "bluetooth", item: bluetooth },
        { name: "volume", item: volume },
        { name: "battery", item: battery },
        { name: "calendar", item: clock },
        { name: "power", item: power },
        { name: "media", item: visualizer }
    ]

    // Hit zones hug the items: the gaps between them are neutral, so a diagonal
    // move towards the open panel doesn't clip a neighbour
    function within(item, x) {
        const left = item.mapToItem(null, 0, 0).x - 4;
        return item.visible && x >= left && x <= left + item.width + 8;
    }

    function triggerAt(x) {
        return triggers.find(t => within(t.item, x)) ?? null;
    }

    function itemAt(x) {
        for (const item of [...status.children, clock, power])
            if (within(item, x))
                return item;
        return null;
    }

    function trayAt(x) {
        return tray.children.find(c => c.modelData && within(c, x)) ?? null;
    }

    property var pending: null

    // Trigger under the pointer, for the hover pill
    property Item hovered: null
    // Items that open a popout get its sound instead
    onHoveredChanged: if (hovered && !triggers.some(t => t.item === hovered)) Sfx.play("hover")
    readonly property Item litItem: triggers.find(t => t.name === popouts.current)?.item ?? null
    // While a panel is open the pill marks its item, so it moves together with the panel
    // The clock is a pill of its own and lights up by itself, the visualizer needs none
    readonly property Item pillItem: {
        const item = popouts.open ? litItem : hovered;
        return item === clock || item === visualizer ? null : item;
    }

    function track() {
        if (!hover.hovered || hover.point.position.y >= Theme.barHeight)
            hovered = null;
        if (!hover.hovered) {
            pending = null;
            return popouts.leave();
        }
        const p = hover.point.position;
        if (p.y >= Theme.barHeight) {
            pending = null;
            return popouts.stay();
        }
        const t = triggerAt(p.x);
        hovered = t?.item ?? trayAt(p.x);
        if (!t) {
            const item = itemAt(p.x);
            pending = null;
            // A gap inside the row keeps the panel, anything else closes it
            const r = rightRow.mapToItem(null, 0, 0).x;
            if (!item && popouts.open && p.x >= r && p.x <= r + rightRow.width)
                return popouts.stay();
            return popouts.leave();
        }
        if (!popouts.open || t.name === popouts.current) {
            pending = null;
            return popouts.show(t.name, t.item);
        }
        // Switching to another item waits for the pointer to settle on it
        popouts.stay();
        if (pending !== t) {
            pending = t;
            switchDelay.restart();
        }
    }

    Timer {
        id: switchDelay
        interval: 140
        onTriggered: if (root.pending) {
            popouts.show(root.pending.name, root.pending.item);
            root.pending = null;
        }
    }

    // Opened from the keyboard (Ctrl+Alt+Del) on the focused monitor only
    IpcHandler {
        target: "power"
        enabled: root.screen?.name === Hyprland.focusedMonitor?.name

        function toggle(): void {
            if (popouts.current === "power") {
                popouts.close();
                return;
            }
            popouts.close();
            popouts.show("power", power);
            popouts.pinned = true;
        }
    }

    IpcHandler {
        target: "media"
        enabled: root.screen?.name === Hyprland.focusedMonitor?.name

        function toggle(): void {
            if (popouts.current === "media")
                popouts.close();
            else
                root.openMedia(false);
        }
    }

    function openMedia(fx) {
        popouts.close();
        popouts.show("media", visualizer);
        popouts.pinned = true;
        popouts.fx = fx;
    }

    HyprlandFocusGrab {
        windows: [root]
        active: popouts.pinned
        onCleared: popouts.close()
    }

    // Caffeine holds an idle inhibitor on the bar's always-visible surface
    IdleInhibitor {
        window: root
        enabled: Caffeine.enabled
    }

    Item {
        anchors.fill: parent

        HoverHandler {
            id: hover
            onPointChanged: root.track()
            onHoveredChanged: root.track()
        }

        Connections {
            target: popouts
            function onBusyChanged() { root.track(); }
        }

        // Below the bar, so panels can slide out from behind it
        Popouts {
            id: popouts
            anchors.fill: parent
        }

        Rectangle {
            id: bar

            width: parent.width
            height: Theme.barHeight
            color: Theme.bg

            Rectangle {
                id: leftPill
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: leftRow.implicitWidth + 28
                height: 30
                radius: height / 2
                color: Theme.surface

                Row {
                    id: leftRow
                    anchors.centerIn: parent
                    spacing: 16

                    OsLogo {}
                    Workspaces { screen: root.screen }
                    Visualizer {
                        id: visualizer
                        // Right click opens the player with its effects section, or folds it back
                        onFxRequested: {
                            if (popouts.current !== "media")
                                return root.openMedia(true);
                            if (popouts.fx && popouts.pinned)
                                return popouts.close();
                            popouts.fx = true;
                            popouts.pinned = true;
                        }
                    }
                }
            }

            // Tray background, drawn under the hover pill like the status group's
            Rectangle {
                anchors.left: leftPill.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: tray.width + 28
                height: 30
                radius: height / 2
                color: Theme.surface
                visible: tray.count > 0
            }

            // Background of the status group, drawn under the hover pill
            Rectangle {
                x: rightRow.x + status.x - 14
                width: status.width + 28
                height: 30
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: Theme.surface
            }

            // State layer behind the hovered item, gliding between items
            Rectangle {
                id: pill

                // Keeps the last spot while fading out
                readonly property Item target: root.pillItem

                function place() {
                    if (!target)
                        return;
                    x = target.mapToItem(bar, 0, 0).x - 8;
                    width = target.width + 16;
                }

                onTargetChanged: place()

                Connections {
                    target: pill.target
                    function onWidthChanged() { pill.place(); }
                    function onXChanged() { pill.place(); }
                }
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: Qt.alpha(Theme.secondary, popouts.open ? 0.16 : 0.12)
                opacity: root.pillItem ? 1 : 0

                Behavior on x { enabled: pill.opacity > 0; NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
                Behavior on width { enabled: pill.opacity > 0; NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
                Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            }

            Tray {
                id: tray
                x: leftPill.x + leftPill.width + 8 + 14
                visible: count > 0
            }

            Row {
                id: rightRow

                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 24

                Recording {}

                Row {
                    id: status
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    KbLayout { id: kb; visible: Keyboard.layouts.length > 1; lit: popouts.current === "keyboard" }
                    NetworkIcon { id: network; lit: popouts.current === "network" }
                    VpnIcon { id: vpn; lit: popouts.current === "vpn" }
                    Bluetooth { id: bluetooth; lit: popouts.current === "bluetooth" }
                    Volume { id: volume; lit: popouts.current === "volume" }
                    Battery { id: battery; lit: popouts.current === "battery" }
                }

                Clock { id: clock; lit: popouts.current === "calendar" }
                PowerButton { id: power; lit: popouts.current === "power" }
            }
        }

    }
}
