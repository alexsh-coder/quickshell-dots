import QtQuick
import qs.config
import qs.components

// Round icon button of the media popout: a Material icon or a Nerd Font glyph
Item {
    id: btn

    property string icon
    property int iconSize: 22
    property int diameter: 38
    property bool active: false
    property real fill: 1
    // Nerd Font glyph drawn instead of the Material icon
    property string nerd
    // Prev/next are always drawn in the text colour
    property bool plain: false
    signal clicked

    width: diameter
    height: diameter
    opacity: enabled ? 1 : 0.35

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.alpha(Theme.text, btnMouse.pressed ? 0.14 : 0.08)
        opacity: btnMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    Icon {
        anchors.centerIn: parent
        visible: !btn.nerd
        text: btn.icon
        font.pixelSize: btn.iconSize
        fill: btn.fill
        color: btn.plain ? Theme.text : btn.active ? Theme.accent : Theme.subtext
        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Behavior on fill { NumberAnimation { duration: Theme.anim } }
    }

    NerdIcon {
        anchors.centerIn: parent
        visible: !!btn.nerd
        text: btn.nerd
        font.pixelSize: btn.iconSize
        color: btn.plain ? Theme.text : btn.active ? Theme.accent : Theme.subtext
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
