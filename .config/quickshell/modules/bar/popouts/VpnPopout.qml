import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    property bool managing: false

    onHereChanged: {
        if (here)
            Vpn.test();
        else
            managing = false;
    }
    onManagingChanged: {
        popouts.pinned = managing;
        if (managing)
            Vpn.loadSubs();
    }
    Connections {
        target: root.popouts
        function onPinnedChanged() {
            if (!root.popouts.pinned)
                root.managing = false;
        }
    }

    implicitWidth: 300
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 10

        Item {
            width: parent.width
            height: 28

            Icon {
                id: head
                anchors.verticalCenter: parent.verticalCenter
                text: Vpn.on ? "vpn_key" : "vpn_key_off"
                font.pixelSize: 20
                color: Vpn.on ? Theme.accent : Theme.subtext
            }

            Column {
                anchors.left: head.right
                anchors.leftMargin: 10
                anchors.right: actions.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    text: "VPN"
                    font.pixelSize: 14
                }

                Label {
                    width: parent.width
                    text: Vpn.busy ? (Vpn.on ? "Disconnecting…" : "Connecting…")
                        : !Vpn.on ? "Off"
                        : Vpn.split(Vpn.current).name || "Connecting…"
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    color: Theme.subtext
                }
            }

            Row {
                id: actions
                anchors.right: toggle.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: !Vpn.busy

                RoundButton {
                    icon: "speed"
                    spinning: Vpn.testing
                    onClicked: Vpn.test()
                }

                RoundButton {
                    icon: "sync"
                    spinning: Vpn.updating
                    onClicked: Vpn.update()
                }
            }

            Toggle {
                id: toggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: Vpn.on
                onToggled: if (!Vpn.busy) Vpn.toggle()
            }
        }

        // Active subscription; opens the manager
        Rectangle {
            width: parent.width
            height: 34
            radius: Theme.radius - 2
            visible: Vpn.subs.length > 0 || root.managing
            color: root.managing ? Theme.surface : subMouse.containsMouse ? Theme.surface : Qt.alpha(Theme.surface, 0)
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            Icon {
                id: subIcon
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "rss_feed"
                font.pixelSize: 17
                color: Theme.subtext
            }

            Label {
                anchors.left: subIcon.right
                anchors.leftMargin: 10
                anchors.right: chevron.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: Vpn.subNow?.name ?? "Subscriptions"
                elide: Text.ElideRight
                font.pixelSize: 13
                color: Theme.subtext
            }

            Icon {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "expand_more"
                font.pixelSize: 18
                color: Theme.subtext
                rotation: root.managing ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: subMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.managing = !root.managing
            }
        }

        Column {
            width: parent.width
            spacing: 2
            visible: root.managing

            Repeater {
                model: Vpn.subs
                delegate: SubRow {}
            }

            // Add field
            Rectangle {
                id: box

                width: parent.width
                height: 36
                radius: Theme.radius - 2
                color: Theme.surface
                border.width: 1
                border.color: Vpn.subError ? Theme.urgent : field.activeFocus ? Theme.accent : Theme.muted
                Behavior on border.color { ColorAnimation { duration: Theme.anim } }

                TextInput {
                    id: field

                    anchors.left: parent.left
                    anchors.right: addButtons.left
                    anchors.margins: 12
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.accent, 0.4)
                    clip: true
                    enabled: root.managing

                    onEnabledChanged: {
                        text = "";
                        if (enabled)
                            forceActiveFocus();
                    }
                    onTextChanged: Vpn.subError = ""
                    onAccepted: if (text.trim() !== "" && !Vpn.subBusy) Vpn.subAdd(text)
                    Keys.onEscapePressed: root.managing = false

                    Label {
                        visible: !field.text
                        text: "Subscription link"
                        font.pixelSize: 13
                        color: Theme.subtext
                    }
                }

                Row {
                    id: addButtons

                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    RoundButton {
                        icon: "content_paste"
                        onClicked: {
                            field.selectAll();
                            field.paste();
                            field.forceActiveFocus();
                        }
                    }

                    RoundButton {
                        icon: "arrow_forward"
                        spinning: Vpn.subBusy
                        onClicked: field.accepted()
                    }
                }
            }

            Label {
                visible: Vpn.subError !== ""
                width: parent.width
                leftPadding: 4
                text: Vpn.subError
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: Theme.urgent
            }

            Connections {
                target: Vpn
                function onSubsChanged() {
                    if (!Vpn.subError)
                        field.text = "";
                }
            }
        }

        Column {
            width: parent.width
            spacing: 2
            visible: Vpn.servers.length > 0 && !root.managing

            Repeater {
                model: Vpn.servers
                delegate: ServerRow {}
            }
        }
    }

    component ServerRow: Rectangle {
        id: row

        required property string modelData
        readonly property bool isAuto: modelData === "auto"
        readonly property bool current: modelData === Vpn.selected
        readonly property var info: Vpn.split(modelData)
        readonly property var delay: Vpn.delays[modelData]

        width: parent.width
        height: 40
        radius: Theme.radius - 2
        color: current ? Qt.alpha(Theme.accent, 0.12) : mouse.containsMouse ? Theme.surface : Qt.alpha(Theme.surface, 0)
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Rectangle {
            id: badge
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 24
            radius: 6
            color: flagImg.status === Image.Ready ? Qt.alpha(Theme.surface, 0) : row.current ? Theme.accent : Theme.surface
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            Icon {
                visible: row.isAuto
                anchors.centerIn: parent
                text: "bolt"
                font.pixelSize: 16
                color: row.current ? Theme.bg : Theme.subtext
            }

            ClippingRectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                visible: flagImg.status === Image.Ready

                Image {
                    id: flagImg
                    anchors.fill: parent
                    source: Vpn.flag(row.info.code)
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectCrop
                }
            }

            // Selection ring over the flag
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
                visible: row.current && flagImg.status === Image.Ready
            }

            Text {
                visible: row.info.flag !== "" && flagImg.status !== Image.Ready
                anchors.centerIn: parent
                text: row.info.flag
                font.family: "Noto Color Emoji"
                font.pixelSize: 16
            }

            Label {
                visible: !row.isAuto && row.info.flag === ""
                anchors.centerIn: parent
                text: row.info.code || "··"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: row.current ? Theme.bg : Theme.subtext
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 12
            anchors.right: ping.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Label {
                width: parent.width
                text: row.isAuto ? "Auto" : row.info.name
                elide: Text.ElideRight
                font.pixelSize: 13
                color: row.current ? Theme.text : Theme.subtext
            }

            Label {
                visible: row.isAuto && Vpn.autoPick !== ""
                width: parent.width
                text: Vpn.split(Vpn.autoPick).name
                elide: Text.ElideRight
                font.pixelSize: 11
                color: Theme.subtext
            }
        }

        Label {
            id: ping
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: row.delay === undefined ? "" : row.delay > 0 ? row.delay + " ms" : "—"
            font.pixelSize: 12
            color: row.delay === 0 ? Theme.urgent : Theme.subtext
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!row.current && Vpn.on) Vpn.use(row.modelData)
        }
    }

    component SubRow: Rectangle {
        id: sub

        required property var modelData
        readonly property bool current: modelData.id === Vpn.activeSub
        property bool confirming: false

        width: parent.width
        height: 40
        radius: Theme.radius - 2
        color: current ? Qt.alpha(Theme.accent, 0.12) : subHover.containsMouse ? Theme.surface : Qt.alpha(Theme.surface, 0)
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Timer {
            id: confirmTimer
            interval: 3000
            onTriggered: sub.confirming = false
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: del.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Label {
                width: parent.width
                text: sub.modelData.name
                elide: Text.ElideRight
                font.pixelSize: 13
                color: sub.current ? Theme.text : Theme.subtext
            }

            Label {
                width: parent.width
                text: sub.confirming ? "Press again to delete" : sub.modelData.servers ? `${sub.modelData.servers} servers · ${sub.modelData.host}` : sub.modelData.host
                elide: Text.ElideRight
                font.pixelSize: 11
                color: sub.confirming ? Theme.urgent : Theme.subtext
            }
        }

        MouseArea {
            id: subHover
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: del.left
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!sub.current && !Vpn.subBusy) Vpn.subUse(sub.modelData.id)
        }

        RoundButton {
            id: del
            anchors.right: parent.right
            anchors.rightMargin: 8
            icon: "delete"
            danger: sub.confirming
            spinning: Vpn.subBusy && sub.confirming
            onClicked: {
                if (sub.confirming) {
                    Vpn.subRemove(sub.modelData.id);
                } else {
                    sub.confirming = true;
                    confirmTimer.restart();
                }
            }
        }
    }

    component RoundButton: Rectangle {
        id: btn

        property string icon
        property bool spinning: false
        property bool danger: false
        signal clicked

        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 13
        color: danger ? Qt.alpha(Theme.urgent, 0.25) : btnMouse.containsMouse ? Qt.alpha(Theme.text, 0.12) : Qt.alpha(Theme.text, 0)
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Icon {
            id: glyph
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: 17
            color: btn.danger ? Theme.urgent : btn.spinning ? Theme.accent : Theme.subtext

            SequentialAnimation on opacity {
                running: btn.spinning
                loops: Animation.Infinite
                onRunningChanged: if (!running) glyph.opacity = 1
                NumberAnimation { to: 0.35; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!btn.spinning) btn.clicked()
        }
    }
}
