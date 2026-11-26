import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.config
import qs.services

// Mirrored spectrum bars that read like a waveform; dims while paused, folds away without a track.
// Hover opens the player panel, click plays/pauses, right click opens it with the music effects,
// wheel changes intensity.
Item {
    id: root

    readonly property int count: 12
    readonly property int barWidth: 3
    readonly property int gap: 2
    readonly property int fullWidth: count * barWidth + (count - 1) * gap
    readonly property list<real> values: Cava.downsample(count)
    readonly property bool present: Players.music.some(p => p.trackTitle)
    signal fxRequested

    implicitWidth: Cava.active || present ? fullWidth : 0
    implicitHeight: 24
    anchors.verticalCenter: parent.verticalCenter
    opacity: Cava.active ? 1 : present ? 0.4 : 0
    visible: implicitWidth > 0

    Behavior on implicitWidth { NumberAnimation { duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    Item {
        anchors.fill: parent
        clip: true

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.gap

            Repeater {
                model: root.count

                Rectangle {
                    required property int index

                    anchors.verticalCenter: parent.verticalCenter
                    width: root.barWidth
                    height: Math.max(root.barWidth, root.values[index] * root.implicitHeight)
                    radius: root.barWidth / 2
                    color: Theme.tintAccent

                    Behavior on height { NumberAnimation { duration: 50 } }
                }
            }
        }

        layer.enabled: MusicFx.glow && Cava.active
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.tintAccent
            shadowBlur: 0.6
            shadowOpacity: Math.min(1, (0.4 + Cava.level * 0.6) * MusicFx.gain("glow"))
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.fxRequested();
                return;
            }
            const p = Players.music.find(p => p.isPlaying) ?? Players.music[0];
            if (p?.canTogglePlaying)
                p.togglePlaying();
        }
        onWheel: wheel => MusicFx.setIntensity(MusicFx.intensity + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
    }
}
