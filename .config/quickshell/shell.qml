import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: "#1a1b26"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: Hyprland.workspaces

                    Rectangle {
                        required property var modelData
                        visible: modelData.id > 0 // hide special workspaces

                        width: 22
                        height: 22
                        radius: 6
                        color: modelData.focused ? "#33ccff" : "#2a2b3d"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.id
                            color: modelData.focused ? "#1a1b26" : "#c0caf5"
                            font.family: "CaskaydiaCove Nerd Font"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // Hyprland config is Lua, so dispatch takes hl.dsp.* syntax
                            onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + modelData.id + " })")
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: "#c0caf5"
                font.family: "CaskaydiaCove Nerd Font"
                font.pixelSize: 14
                font.bold: true
            }
        }
    }
}
