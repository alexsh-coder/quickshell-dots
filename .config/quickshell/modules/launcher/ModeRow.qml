import QtQuick
import Quickshell
import qs.config
import qs.components

MouseArea {
    id: root

    required property var modelData
    required property int index
    required property var launcher
    property bool current: false

    hoverEnabled: true
    onPositionChanged: mouse => {
        if (launcher.cursorMoved(root, mouse.x, mouse.y))
            ListView.view.currentIndex = index;
    }
    onClicked: launcher.activateItem(modelData, false)

    Item {
        id: iconSlot
        x: 12
        width: 32
        height: 32
        anchors.verticalCenter: parent.verticalCenter

        AppIcon {
            visible: !!root.modelData?.appIcon
            anchors.fill: parent
            implicitSize: 32
            icon: root.modelData?.appIcon ?? ""
        }

        Text {
            visible: !!root.modelData?.glyph
            anchors.centerIn: parent
            font.family: root.modelData?.glyphFont ?? ""
            font.pixelSize: 24
            color: root.current ? Theme.accent : Theme.text
            text: root.modelData?.glyph ?? ""
        }

        Icon {
            visible: !!root.modelData?.icon
            anchors.centerIn: parent
            font.pixelSize: 24
            color: root.modelData?.armed ? Theme.urgent : Theme.accent
            text: root.modelData?.icon ?? ""
        }
    }

    Column {
        anchors.left: iconSlot.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
            width: parent.width
            elide: Text.ElideRight
            text: root.modelData?.title ?? ""
            color: root.current ? Theme.accent : Theme.text
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        Label {
            visible: text
            width: parent.width
            elide: Text.ElideMiddle
            font.pixelSize: 12
            font.weight: Font.Normal
            text: root.modelData?.subtitle ?? ""
            color: root.modelData?.armed ? Theme.urgent : Theme.subtext
        }
    }
}
