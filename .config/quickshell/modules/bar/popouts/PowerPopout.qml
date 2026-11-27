import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// Lock and suspend fire on click; logout, reboot and shutdown fill up while held
Item {
    id: root

    required property Item popouts
    property bool here: false

    property string hint: ""
    // Keyboard selection, only while the panel is pinned open from the keyboard
    property int selected: -1
    onSelectedChanged: if (selected >= 0) Sfx.play("hoverPop")
    property string uptime: ""

    readonly property var actions: [
        { icon: "lock", label: "Lock", hold: false, run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        { icon: "bedtime", label: "Suspend", hold: false, run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { icon: "logout", label: "Log out", hold: true, run: () => Hyprland.dispatch("hl.dsp.exit()") },
        { icon: "restart_alt", label: "Reboot", hold: true, run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { icon: "power_settings_new", label: "Shut down", hold: true, run: () => Quickshell.execDetached(["systemctl", "poweroff"]) }
    ]

    implicitWidth: buttons.implicitWidth + Theme.pad * 2
    implicitHeight: buttons.implicitHeight + caption.anchors.topMargin + caption.height + Theme.padTop + Theme.pad

    onHereChanged: {
        if (here)
            uptimeProc.running = true;
        else
            selected = -1;
    }

    readonly property bool keyboard: here && popouts.pinned
    onKeyboardChanged: if (keyboard) {
        selected = 0;
        hint = actions[0].label + (actions[0].hold ? " · hold" : "");
        forceActiveFocus();
    }

    function select(i) {
        selected = (i + actions.length) % actions.length;
        hint = actions[selected].label + (actions[selected].hold ? " · hold" : "");
    }

    Keys.onPressed: event => {
        const btn = buttonsRepeater.itemAt(selected);
        if (event.key === Qt.Key_Escape)
            popouts.close();
        else if (event.key === Qt.Key_Left)
            select(selected - 1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
            select(selected + 1);
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && btn && !event.isAutoRepeat)
            btn.press();
        else
            return;
        event.accepted = true;
    }

    Keys.onReleased: event => {
        const btn = buttonsRepeater.itemAt(selected);
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && btn && !event.isAutoRepeat) {
            btn.release();
            event.accepted = true;
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

    // Clears the caption only when leaving the whole row, not the gaps between buttons
    HoverHandler {
        id: rowHover
        onHoveredChanged: if (!hovered) root.hint = ""
    }

    Row {
        id: buttons

        x: Theme.pad
        y: Theme.padTop
        spacing: 8

        Repeater {
            id: buttonsRepeater
            model: root.actions

            Rectangle {
                id: btn

                required property var modelData
                property real progress: 0

                width: 52
                height: 52
                radius: width / 2
                readonly property bool active: mouse.containsMouse || (root.keyboard && root.selected === index)
                required property int index
                border.width: root.keyboard && root.selected === index ? 1 : 0
                border.color: Qt.alpha(Theme.accent, 0.6)
                // Opaque tint: fading towards a translucent color overshoots and flashes
                color: active ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
                Behavior on color { ColorAnimation { duration: Theme.anim } }

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
                    font.pixelSize: 24
                    fill: 0
                    color: btn.progress > 0.5 ? Theme.bg : Theme.text
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
                    root.popouts.close();
                    progress = 0;
                    modelData.run();
                }

                MouseArea {
                    id: mouse
                    onPressedChanged: if (!pressed && containsMouse) Sfx.tap("clickPop")

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.select(btn.index)
                    onPressed: if (btn.modelData.hold) { drain.stop(); charge.restart(); }
                    onReleased: if (btn.modelData.hold && btn.progress < 1) { charge.stop(); drain.restart(); }
                    onCanceled: { charge.stop(); drain.restart(); }
                    onClicked: if (!btn.modelData.hold) btn.fire()
                }
            }
        }
    }

    Label {
        id: caption

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: buttons.bottom
        anchors.topMargin: 10
        text: root.hint || root.uptime
        font.pixelSize: 13
        color: root.hint ? Theme.text : Theme.subtext
    }
}
