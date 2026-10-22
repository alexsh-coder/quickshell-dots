import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// Hot edge on the left side of every screen: touching it slides a tab out,
// clicking the tab opens desktop edit mode. On the Top layer, so fullscreen windows cover it
Variants {
    id: root

    // Hot zone along the left edge, as a share of the screen height
    readonly property real edgeSpan: 0.15

    model: Quickshell.screens

    PanelWindow {
        id: edge

        required property var modelData
        property bool peek: false
        readonly property bool out: peek && !Desk.editing

        screen: modelData
        WlrLayershell.namespace: "qs-edge"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        anchors.left: true
        implicitWidth: 64
        implicitHeight: Math.max(tab.height + 24, Math.round(modelData.height * root.edgeSpan))
        color: "transparent"
        mask: Region {
            item: strip
            Region { item: tab }
        }

        HoverHandler {
            id: edgeHover
        }

        Timer {
            running: edgeHover.hovered && !edge.peek && !Desk.editing
            interval: 120
            onTriggered: edge.peek = true
        }

        Timer {
            running: !edgeHover.hovered && edge.peek
            interval: 450
            onTriggered: edge.peek = false
        }

        Item {
            id: strip
            width: 1
            height: parent.height
        }

        // Pokes out of the edge; its left end hides past the screen,
        // so only the right corners show rounded
        Rectangle {
            id: tab

            readonly property bool hot: tabArea.containsMouse
            property int visibleWidth: hot ? 46 : 40
            property real reveal: edge.out ? 1 : 0

            x: visibleWidth * reveal - width
            anchors.verticalCenter: parent.verticalCenter
            width: visibleWidth + radius
            height: 48
            radius: 16
            color: Qt.alpha(Theme.bg, 0.85)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, hot ? 0.45 : 0.25)
            opacity: reveal

            Behavior on reveal {
                NumberAnimation {
                    duration: edge.out ? Theme.animSpatial : 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: edge.out ? Theme.spatial : Theme.emphasizedAccel
                }
            }
            Behavior on visibleWidth { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            Behavior on border.color { ColorAnimation { duration: Theme.anim } }

            Icon {
                x: tab.radius + (tab.visibleWidth - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                text: "widgets"
                font.pixelSize: 21
                color: tab.hot ? Theme.accent : Theme.subtext
            }

            MouseArea {
                id: tabArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    edge.peek = false;
                    Desk.editing = true;
                }
            }
        }
    }
}
