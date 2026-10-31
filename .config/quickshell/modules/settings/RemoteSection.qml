import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Column {
    id: root

    property bool shown: false

    spacing: 6

    component Field: Rectangle {
        id: box

        property alias text: field.text
        property string placeholder
        signal edited(string value)

        width: 200
        height: 36
        radius: Theme.radius - 2
        color: Theme.surface
        border.width: 1
        border.color: field.activeFocus ? Theme.accent : Theme.muted
        Behavior on border.color { ColorAnimation { duration: Theme.anim } }

        TextInput {
            id: field

            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.font
            font.pixelSize: 13
            color: Theme.text
            selectionColor: Qt.alpha(Theme.accent, 0.4)
            clip: true
            onEditingFinished: box.edited(text.trim().replace(/\s+/g, " "))
        }

        Label {
            anchors.fill: field
            verticalAlignment: Text.AlignVCenter
            text: box.placeholder
            color: Theme.subtext
            font.pixelSize: 13
            visible: !field.text && !field.activeFocus
        }
    }

    SectionTitle { text: "Remote PC" }

    SettingRow {
        label: "Address"
        hint: "LAN IP or hostname used by VNC and ssh helpers"

        Field {
            text: Settings.remoteHost
            placeholder: "192.168.0.100"
            onEdited: v => Settings.remoteHost = v
        }
    }

    SettingRow {
        label: "User"
        hint: "ssh user there; several separated by spaces are tried in order"

        Field {
            text: Settings.remoteUser
            placeholder: Quickshell.env("USER")
            onEdited: v => Settings.remoteUser = v
        }
    }
}
