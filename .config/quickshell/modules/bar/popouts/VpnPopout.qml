import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    onHereChanged: if (here) Vpn.test()

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
                visible: Vpn.on && !Vpn.busy

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

        Column {
            width: parent.width
            spacing: 2
            visible: Vpn.on && Vpn.servers.length > 0

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
            onClicked: if (!row.current) Vpn.use(row.modelData)
        }
    }

    component RoundButton: Rectangle {
        id: btn

        property string icon
        property bool spinning: false
        signal clicked

        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 13
        color: btnMouse.containsMouse ? Qt.alpha(Theme.text, 0.12) : Qt.alpha(Theme.text, 0)
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Icon {
            id: glyph
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: 17
            color: btn.spinning ? Theme.accent : Theme.subtext

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
