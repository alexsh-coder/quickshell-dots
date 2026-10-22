import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

PanelWindow {
    id: root

    readonly property int gap: 10
    readonly property int cardWidth: 380
    readonly property int maxShown: 5

    screen: Quickshell.screens[0]

    WlrLayershell.namespace: "notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal

    anchors {
        top: true
        right: true
    }
    margins.top: root.gap
    margins.right: root.gap

    // Tall enough for a full stack; only the cards take input
    implicitWidth: root.cardWidth
    implicitHeight: screen ? screen.height * 0.8 : 900
    color: "transparent"
    // Stays mapped: a surface mapped together with its first card shows it
    // already in place, skipping the slide-in
    mask: Region { item: list.contentItem }

    ListView {
        id: list

        width: parent.width
        height: Math.min(contentHeight, parent.height)
        interactive: false
        spacing: root.gap

        model: ScriptModel {
            values: Notifs.popups.slice(0, root.maxShown)
        }

        delegate: Toast {}

        add: Transition {
            NumberAnimation { property: "x"; from: root.cardWidth + root.gap; to: 0; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial }
        }

        remove: Transition {
            NumberAnimation { property: "x"; to: root.cardWidth + root.gap; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedAccel }
        }

        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
            NumberAnimation { property: "x"; to: 0; duration: Theme.anim }
        }
    }
}
