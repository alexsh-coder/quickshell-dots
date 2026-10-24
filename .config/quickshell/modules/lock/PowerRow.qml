import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.components

// Bottom of the lockscreen: sleep fires on click, the rest fill up while held
Row {
    id: root

    spacing: 36

    readonly property var actions: [
        { icon: "bedtime", label: "Sleep", hold: false, run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { icon: "restart_alt", label: "Restart", hold: true, run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { icon: "power_settings_new", label: "Shut Down", hold: true, run: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
        { icon: "logout", label: "Logout", hold: true, run: () => Hyprland.dispatch("hl.dsp.exit()") }
    ]

    Repeater {
        model: root.actions

        Item {
            id: btn

            required property var modelData
            property real progress: 0
            readonly property color tone: mouse.containsMouse || progress > 0 ? Theme.accent : Qt.rgba(1, 1, 1, 0.6)

            implicitWidth: Math.max(64, col.implicitWidth)
            implicitHeight: col.implicitHeight

            Column {
                id: col
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48
                    height: 48

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.12 : 0.06)
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }

                    // Hold progress, a disc growing from the center
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.accent
                        scale: btn.progress
                        visible: btn.progress > 0
                    }

                    Icon {
                        anchors.centerIn: parent
                        text: btn.modelData.icon
                        font.pixelSize: 22
                        fill: 0
                        weight: 400
                        color: btn.progress > 0.5 ? "black" : btn.tone
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: btn.modelData.label
                    font.pixelSize: 12
                    color: btn.tone
                    Behavior on color { ColorAnimation { duration: Theme.anim } }
                }

            }

            NumberAnimation {
                id: charge
                target: btn
                property: "progress"
                to: 1
                duration: 750 * (1 - btn.progress)
                easing.type: Easing.InQuad
                onFinished: if (btn.progress >= 1) { btn.progress = 0; btn.modelData.run(); }
            }

            NumberAnimation {
                id: drain
                target: btn
                property: "progress"
                to: 0
                duration: 300
                easing.type: Easing.OutCubic
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: if (btn.modelData.hold) { drain.stop(); charge.restart(); }
                onReleased: if (btn.modelData.hold && btn.progress < 1) { charge.stop(); drain.restart(); }
                onCanceled: { charge.stop(); drain.restart(); }
                onClicked: if (!btn.modelData.hold) btn.modelData.run()
            }
        }
    }
}
