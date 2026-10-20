import QtQuick
import qs.config
import qs.components

Item {
    property bool lit: false

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    NerdIcon {
        id: icon
        anchors.centerIn: parent
        // nf-md power
        text: "\u{f0425}"
        color: Theme.accent
        scale: parent.lit ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
    }
}
