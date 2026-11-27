import QtQuick
import qs.config
import qs.services

// Thick pill slider, 0..1. Emits moved() while dragging or scrolling
Item {
    id: root

    property real value
    property bool dim: false
    readonly property bool pressed: drag.pressed
    signal moved(real v)
    onMoved: Sfx.play("slide", 45)

    implicitHeight: 24

    function clamp(v) {
        return Math.max(0, Math.min(1, v));
    }

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: drag.pressed ? 12 : 10
        radius: height / 2
        color: Theme.muted
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
            id: fill

            property real frac: root.clamp(root.value)
            width: Math.max(track.height, track.width * frac)
            height: parent.height
            radius: parent.radius
            color: root.dim ? Theme.subtext : Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.anim } }
            // External changes glide, dragging follows the pointer directly
            Behavior on frac { enabled: !drag.pressed; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        }
    }

    Rectangle {
        x: Math.max(0, Math.min(root.width - width, fill.width - width / 2 - 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: drag.pressed ? 24 : drag.containsMouse ? 22 : 18
        radius: 2
        color: Theme.text
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: drag
        onContainsMouseChanged: if (containsMouse) Sfx.play("hover")

        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.moved(root.clamp((mouse.x - 6) / root.width))
        onPositionChanged: mouse => { if (pressed) root.moved(root.clamp((mouse.x - 6) / root.width)); }
    }
}
