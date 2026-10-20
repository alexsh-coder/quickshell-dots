import QtQuick
import Quickshell.Services.Mpris
import qs.config
import qs.components
import qs.services

// Bottom of the lockscreen: a mirrored spectrum with the bass in the middle, and the track under it
Item {
    id: root

    readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property bool active: !!player && !!player.trackTitle

    readonly property int half: 24
    readonly property int barWidth: 4
    readonly property int barGap: 5
    readonly property int barHeight: 44
    readonly property var levels: Cava.downsample(half)

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight
    visible: active && opacity > 0

    Column {
        id: column
        spacing: 16

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.barGap

            Repeater {
                model: root.half * 2

                Item {
                    required property int index
                    readonly property real level: root.levels[index < root.half ? root.half - 1 - index : index - root.half] ?? 0

                    width: root.barWidth
                    height: root.barHeight

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.barWidth
                        height: Math.max(root.barWidth, parent.level * root.barHeight)
                        radius: root.barWidth / 2
                        color: Theme.accent
                        opacity: 0.35 + parent.level * 0.65

                        Behavior on height { NumberAnimation { duration: 60 } }
                    }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 380)
                text: [root.player?.trackTitle, root.player?.trackArtist].filter(s => s).join("  ·  ")
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 14
                elide: Text.ElideRight
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.player?.isPlaying ? "pause" : "play_arrow"
                color: area.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 22

                Behavior on color { ColorAnimation { duration: Theme.anim } }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player?.togglePlaying()
                }
            }
        }
    }
}
