import QtQuick
import Quickshell.Services.Pipewire
import qs.config
import qs.components

Item {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    property bool lit: false

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    PwObjectTracker {
        objects: [root.sink]
    }

    Row {
        id: row
        spacing: 7

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Theme.barIcon
            weight: 500
            text: root.muted ? "no_sound"
                : root.volume >= 0.5 ? "volume_up"
                : root.volume > 0 ? "volume_down"
                : "volume_mute"
            color: root.lit ? Theme.barAccent : root.muted ? Theme.subtext : Theme.secondary
            Behavior on color { ColorAnimation { duration: Theme.anim } }
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
