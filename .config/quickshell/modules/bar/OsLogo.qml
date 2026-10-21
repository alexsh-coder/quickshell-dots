import QtQuick
import Quickshell
import qs.config

Text {
    id: root

    // nf-linux-archlinux
    text: "\uf303"
    font.family: Theme.nerdFont
    font.pixelSize: 24
    color: Theme.tintAccent
    anchors.verticalCenter: parent.verticalCenter
    scale: mouse.pressed ? 0.9 : mouse.containsMouse ? 1.1 : 1
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // "open", not "toggle": a click outside an open launcher already closes it
        onClicked: Quickshell.execDetached(["qs", "ipc", "call", "launcher", "open"])
    }
}
