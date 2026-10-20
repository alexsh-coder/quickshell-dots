import QtQuick
import Quickshell
import qs.config

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            OsLogo {}
            Workspaces { screen: root.screen }
            Visualizer {}
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            KbLayout {}
            Volume {}
            Battery {}
            Clock {}
        }
    }
}
