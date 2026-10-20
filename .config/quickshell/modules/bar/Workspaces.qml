import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

Item {
    id: root

    required property ShellScreen screen
    property int count: 5
    readonly property int dotSize: 15
    readonly property int gap: 7

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor?.activeWorkspace?.id ?? -1
    readonly property int lastId: Math.max(count * 2, ...Hyprland.workspaces.values.map(w => w.id))
    property int first: 1

    onActiveIdChanged: {
        if (activeId < 1)
            return;
        // Keep one neighbour visible on each side of the active dot
        if (activeId < first + 1)
            first = Math.max(1, activeId - 1);
        else if (activeId > first + count - 2)
            first = activeId - count + 2;
    }

    function go(id) {
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
    }

    implicitWidth: count * dotSize + (count - 1) * gap + 2
    implicitHeight: 24
    anchors.verticalCenter: parent.verticalCenter
    clip: true

    Row {
        id: strip

        x: 1 - (root.first - 1) * (root.dotSize + root.gap)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap
        // Moved as a texture while shifting so subpixel offsets don't snap
        layer.enabled: shift.running
        layer.smooth: true

        Behavior on x { NumberAnimation { id: shift; duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }

        Repeater {
            model: root.lastId

            Item {
                id: slot

                required property int index
                readonly property int wsId: index + 1
                readonly property HyprlandWorkspace ws: Hyprland.workspaces.values.find(w => w.id === wsId) ?? null
                readonly property bool active: root.activeId === wsId
                readonly property bool occupied: (ws?.toplevels.values.length ?? 0) > 0

                width: root.dotSize
                height: 24

                Rectangle {
                    anchors.centerIn: parent
                    width: root.dotSize
                    height: root.dotSize
                    radius: root.dotSize / 2
                    scale: slot.active ? 1 : 10 / 15
                    color: slot.ws?.urgent ? Theme.urgent
                         : slot.active ? Theme.accent
                         : slot.occupied ? Theme.subtext
                         : Theme.muted

                    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.anim } }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(slot.wsId)
                }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const step = event.angleDelta.y < 0 ? 1 : -1;
            const next = Math.max(1, Math.min(root.lastId, root.activeId + step));
            if (next !== root.activeId)
                root.go(next);
        }
    }
}
