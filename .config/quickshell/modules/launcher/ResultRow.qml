import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components

MouseArea {
    id: root

    required property DesktopEntry modelData
    required property int index
    required property var launcher
    property bool pinned: false
    property bool current: false
    readonly property alias iconItem: icon
    // Vertical offset for the entrance hop; a transform so it doesn't fight ListView's y
    property real lift: 0

    transform: Translate { y: root.lift }

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onPositionChanged: mouse => {
        if (!launcher.cursorMoved(root, mouse.x, mouse.y))
            return;
        launcher.zone = "list";
        ListView.view.currentIndex = index;
    }
    onClicked: event => {
        if (event.button === Qt.RightButton)
            launcher.togglePin(modelData, icon);
        else
            launcher.launch(modelData);
    }

    IconImage {
        id: icon
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: 32
        source: Quickshell.iconPath(root.modelData.icon, "application-x-executable")
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: pin.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
            width: parent.width
            elide: Text.ElideRight
            text: root.modelData.name
            color: root.current ? Theme.accent : Theme.text
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        Label {
            visible: text
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: 12
            font.weight: Font.Normal
            text: root.modelData.comment || root.modelData.genericName
            color: Theme.subtext
        }
    }

    Icon {
        id: pin
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "push_pin"
        font.pixelSize: 18
        color: Theme.accent
        opacity: root.pinned ? 1 : 0
        scale: root.pinned ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }
    }
}
