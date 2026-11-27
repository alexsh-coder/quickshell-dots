import QtQuick
import qs.config
import qs.components
import qs.services

// Small round icon button
Rectangle {
    id: root

    property string icon
    property bool active: false
    // hovered() plays instead of the usual hover sound
    property bool hoverPreview: false
    signal clicked()
    signal hovered()

    anchors.verticalCenter: parent?.verticalCenter
    width: 30
    height: 30
    radius: 15
    opacity: enabled ? 1 : 0.4
    color: active ? Qt.alpha(Theme.accent, 0.25)
        : area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    Icon {
        anchors.centerIn: parent
        text: root.icon
        font.pixelSize: 18
        color: root.active ? Theme.accent : Theme.text
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) root.hoverPreview ? root.hovered() : Sfx.play("hover")
        onClicked: root.clicked()
    }
}
