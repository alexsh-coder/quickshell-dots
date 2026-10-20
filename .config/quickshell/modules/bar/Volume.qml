import QtQuick
import Quickshell.Services.Pipewire
import qs.config
import qs.components

Item {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    PwObjectTracker {
        objects: [root.sink]
    }

    Row {
        id: row
        spacing: 7

        NerdIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted || root.volume === 0 ? "\u{f0581}"
                : root.volume < 0.34 ? "\u{f057f}"
                : root.volume < 0.67 ? "\u{f0580}"
                : "\u{f057e}"
            color: root.muted ? Theme.subtext : Theme.text
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.volume * 100) + "%"
            color: root.muted ? Theme.subtext : Theme.text
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.sink) root.sink.audio.muted = !root.muted
        onWheel: wheel => {
            if (!root.sink) return;
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            root.sink.audio.volume = Math.max(0, Math.min(1, root.volume + step));
        }
    }
}
