import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// Ctrl+Alt+Del: a shade that drops from the top and bounces off the bottom edge.
// Lock and suspend fire on click; logout, reboot and shutdown fill up while held
Scope {
    id: root

    onOpenChanged: Sfx.play(open ? "open" : "close")

    readonly property bool open: drop.open
    // Set on the first impact, so the buttons pop in as the shade lands
    readonly property bool landed: drop.landed
    property int selected: 0
    property string uptime: ""

    readonly property var actions: [
        { icon: "lock", label: "Lock", hold: false, run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        { icon: "bedtime", label: "Suspend", hold: false, run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { icon: "logout", label: "Log out", hold: true, run: () => Hyprland.dispatch("hl.dsp.exit()") },
        { icon: "restart_alt", label: "Reboot", hold: true, run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { icon: "power_settings_new", label: "Shut down", hold: true, run: () => Quickshell.execDetached(["systemctl", "poweroff"]) }
    ]

    function show() {
        selected = 0;
        uptimeProc.running = true;
        drop.show();
    }

    function hide() {
        drop.hide();
    }

    function select(i) {
        selected = (i + actions.length) % actions.length;
    }

    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }
    }

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text));
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                root.uptime = "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
            }
        }
    }

    DropShade {
        id: drop

        namespace: "powermenu"

        Item {
            id: keys

            anchors.fill: parent
            focus: true

            // Key codes, not text, so both EN and RU layouts work
            Keys.onPressed: event => {
                const btn = repeater.itemAt(root.selected);
                if (event.key === Qt.Key_Escape)
                    root.hide();
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
                    root.select(root.selected - 1);
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
                    root.select(root.selected + 1);
                else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && btn && !event.isAutoRepeat)
                    btn.press();
                else
                    return;
                event.accepted = true;
            }

            Keys.onReleased: event => {
                const btn = repeater.itemAt(root.selected);
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && btn && !event.isAutoRepeat) {
                    btn.release();
                    event.accepted = true;
                }
            }
        }

        // Centered in the space below the bar
        Item {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Theme.barHeight / 2
            width: buttons.implicitWidth
            height: buttons.implicitHeight

            Row {
                id: buttons

                spacing: 40

                Repeater {
                    id: repeater
                    model: root.actions

                    Item {
                        id: btn

                        required property var modelData
                        required property int index
                        property real progress: 0
                        readonly property bool active: root.selected === index

                        width: 140
                        height: 180
                        // Pops in one after another once the shade hits the floor
                        opacity: root.landed && root.open ? 1 : 0
                        scale: root.landed && root.open ? 1 : 0.5
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                        Behavior on scale {
                            SequentialAnimation {
                                PauseAnimation { duration: root.open ? btn.index * 45 : 0 }
                                NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                            }
                        }

                        Rectangle {
                            id: tile

                            width: 140
                            height: 140
                            radius: width / 2
                            color: btn.active ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
                            border.width: btn.active ? 2 : 0
                            border.color: Theme.accent
                            scale: mouse.pressed ? 0.94 : btn.active ? 1.05 : 1
                            Behavior on color { ColorAnimation { duration: Theme.anim } }
                            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }

                            // Soft hover glow around the circle
                            RectangularShadow {
                                z: -1
                                anchors.fill: parent
                                radius: parent.radius
                                blur: 36
                                spread: 2
                                color: Theme.accent
                                opacity: btn.active ? 0.45 : 0
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }

                            // Hold progress, a disc growing from the center
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Theme.accent
                                scale: btn.progress
                                visible: btn.progress > 0
                            }

                            Icon {
                                anchors.centerIn: parent
                                text: btn.modelData.icon
                                font.pixelSize: 60
                                fill: 0
                                weight: 400
                                color: btn.progress > 0.5 ? Theme.bg : btn.active ? Theme.accent : Theme.text
                                Behavior on color { ColorAnimation { duration: Theme.anim } }
                            }
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: btn.modelData.label + (btn.modelData.hold && btn.active ? " · hold" : "")
                            font.pixelSize: 16
                            color: btn.active ? Theme.text : Theme.subtext
                        }

                        NumberAnimation {
                            id: charge
                            target: btn
                            property: "progress"
                            to: 1
                            duration: 750 * (1 - btn.progress)
                            easing.type: Easing.InQuad
                            onFinished: if (btn.progress >= 1) btn.fire()
                        }

                        NumberAnimation {
                            id: drain
                            target: btn
                            property: "progress"
                            to: 0
                            duration: 300
                            easing.type: Easing.OutCubic
                        }

                        function press() {
                            if (modelData.hold) { drain.stop(); charge.restart(); }
                            else fire();
                        }

                        function release() {
                            if (modelData.hold && progress < 1) { charge.stop(); drain.restart(); }
                        }

                        function fire() {
                            root.hide();
                            progress = 0;
                            modelData.run();
                        }

                        MouseArea {
                            id: mouse

                            anchors.fill: tile
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: if (containsMouse) root.select(btn.index)
                            onPressed: btn.press()
                            onReleased: btn.release()
                            onCanceled: { charge.stop(); drain.restart(); }
                        }
                    }
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            text: root.uptime
            font.pixelSize: 15
            color: Theme.subtext
            opacity: root.open && root.uptime ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }
}
