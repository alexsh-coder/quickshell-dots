import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config

MouseArea {
    id: root

    required property string appId
    required property int index
    required property var launcher
    property int size: 56
    property bool selected: false

    readonly property DesktopEntry entry: DesktopEntries.byId(appId)
    readonly property ListView view: ListView.view
    readonly property bool held: drag.active
    property bool dragged: false

    width: size
    height: size
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    drag.target: tile
    drag.axis: Drag.XAxis
    drag.threshold: 6

    onPressed: dragged = false
    onHeldChanged: {
        view.dragging = held;
        if (held) {
            dragged = true;
        } else {
            tile.Drag.drop();
            launcher.savePins();
        }
    }
    onClicked: event => {
        if (dragged)
            return;
        if (event.button === Qt.RightButton)
            launcher.togglePin(entry, null);
        else
            launcher.launch(entry);
    }
    onPositionChanged: mouse => launcher.cursorMoved(root, mouse.x, mouse.y)
    onContainsMouseChanged: {
        if (containsMouse)
            view.hoveredName = entry?.name ?? "";
        else if (view.hoveredName === entry?.name)
            view.hoveredName = "";
    }

    DropArea {
        anchors.fill: parent
        onEntered: drag => root.launcher.movePin(drag.source.slot, root.index)
    }

    Rectangle {
        id: tile

        readonly property int slot: root.index

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.size
        height: root.size
        radius: Theme.radius
        color: root.selected ? Qt.alpha(Theme.accent, 0.16) : (root.containsMouse && root.launcher.mouseActive) || root.held ? Theme.surface : "transparent"
        border.width: 1
        border.color: root.selected ? Qt.alpha(Theme.accent, 0.6) : "transparent"
        opacity: root.launcher.flyId === root.appId ? 0 : 1
        scale: root.held ? 1.12 : root.pressed ? 0.9 : 1

        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Behavior on border.color { ColorAnimation { duration: Theme.anim } }
        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }

        Drag.active: root.held
        Drag.source: tile
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        IconImage {
            anchors.centerIn: parent
            implicitSize: Math.round(root.size * 0.64)
            source: Quickshell.iconPath(root.entry?.icon ?? "", "application-x-executable")
        }

        states: State {
            when: root.held
            ParentChange { target: tile; parent: root.view }
            AnchorChanges {
                target: tile
                anchors.horizontalCenter: undefined
                anchors.verticalCenter: undefined
            }
            PropertyChanges { tile.z: 10 }
        }
    }
}
