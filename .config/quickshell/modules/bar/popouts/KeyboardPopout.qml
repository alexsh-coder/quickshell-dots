import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property var names: ({
        us: "English (US)", gb: "English (UK)", ru: "Russian", ua: "Ukrainian", by: "Belarusian",
        kz: "Kazakh", de: "German", fr: "French", es: "Spanish", it: "Italian", pl: "Polish",
        cz: "Czech", tr: "Turkish", jp: "Japanese", kr: "Korean", cn: "Chinese"
    })

    function code(l) {
        return l === "us" || l === "gb" ? "EN" : l.slice(0, 2).toUpperCase();
    }

    implicitWidth: 260
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 4

        Repeater {
            model: Keyboard.layouts

            Rectangle {
                id: row

                required property string modelData
                required property int index
                readonly property bool current: index === Keyboard.index

                width: parent.width
                height: 40
                radius: Theme.radius - 2
                color: current ? Qt.tint(Theme.bg, Qt.alpha(Theme.accent, 0.12)) : mouse.containsMouse ? Theme.surface : Theme.bg
                Behavior on color { ColorAnimation { duration: Theme.anim } }

                Rectangle {
                    id: badge
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 24
                    radius: 6
                    color: row.current ? Theme.accent : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Label {
                        anchors.centerIn: parent
                        text: root.code(row.modelData)
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: row.current ? Theme.bg : Theme.subtext
                    }
                }

                Label {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.names[row.modelData] ?? row.modelData
                    font.pixelSize: 13
                    color: row.current ? Theme.text : Theme.subtext
                }

                MouseArea {
                    id: mouse
                    onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                    onReleased: if (containsMouse) Sfx.tap("clickPop")
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Keyboard.switchTo(row.index)
                }
            }
        }

        Item {
            width: parent.width
            height: 34

            Icon {
                id: capsIcon
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "keyboard_capslock"
                font.pixelSize: 18
                color: Keyboard.caps ? Theme.accent : Theme.subtext
            }

            Label {
                anchors.left: capsIcon.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "Caps Lock"
                font.pixelSize: 13
                color: Theme.subtext
            }

            Label {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: Keyboard.caps ? "On" : "Off"
                font.pixelSize: 12
                color: Keyboard.caps ? Theme.accent : Theme.subtext
            }
        }
    }
}
