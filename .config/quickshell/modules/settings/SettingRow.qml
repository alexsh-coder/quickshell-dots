import QtQuick
import qs.config
import qs.components

// A setting: name and an optional hint on the left, its control (the children) on the right
Item {
    id: root

    property string label
    property string hint: ""
    default property alias control: slot.data

    width: parent?.width ?? 0
    // Off rows grey out; enabled also stops their controls taking clicks
    opacity: enabled ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    implicitHeight: Math.max(48, text.implicitHeight + 16, slot.childrenRect.height + 16)

    Column {
        id: text

        anchors.left: parent.left
        anchors.right: slot.left
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

    Item {
        id: slot

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
