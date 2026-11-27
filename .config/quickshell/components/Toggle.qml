import QtQuick
import qs.config
import qs.services

Rectangle {
    id: root

    property bool checked
    signal toggled

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.accent : Theme.muted
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    Rectangle {
        x: root.checked ? root.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: mouse.pressed ? 20 : 16
        height: 16
        radius: 8
        color: root.checked ? Theme.bg : Theme.text
        Behavior on x { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
        Behavior on width { NumberAnimation { duration: 140 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Sfx.play(root.checked ? "toggleOff" : "toggleOn");
            root.toggled();
        }
    }
}
