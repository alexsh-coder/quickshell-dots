import QtQuick
import qs.config
import qs.components
import qs.services

// A setting: name and an optional hint on the left, its control (the children) on the right
Item {
    id: root

    property string label
    property string hint: ""
    default property alias control: slot.data
    // Settings key this row edits; a reset button shows while it differs from the default
    property string setting: ""
    property bool changed: setting !== "" && !Settings.isDefault(setting)
    signal reset()

    width: parent?.width ?? 0
    // Off rows grey out; enabled also stops their controls taking clicks
    opacity: enabled ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    implicitHeight: Math.max(48, text.implicitHeight + 16, slot.childrenRect.height + 16)

    Column {
        id: text

        anchors.left: parent.left
        anchors.right: resetIcon.visible ? resetIcon.left : slot.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Label {
            width: parent.width
            text: root.label
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            visible: root.hint !== ""
            text: root.hint
            font.pixelSize: 12
            color: Theme.subtext
            wrapMode: Text.Wrap
        }
    }

    Icon {
        id: resetIcon

        visible: root.changed
        anchors.right: slot.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: "restart_alt"
        font.pixelSize: 20
        color: resetArea.containsMouse ? Theme.accent : Theme.subtext

        MouseArea {
            id: resetArea
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
            onReleased: if (containsMouse) Sfx.tap("click")
            onClicked: {
                if (root.setting !== "")
                    Settings.reset(root.setting);
                root.reset();
            }
        }
    }

    Item {
        id: slot

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
