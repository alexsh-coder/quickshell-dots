import QtQuick
import Quickshell.Widgets
import qs.config
import qs.services

// The playing track: cover, title, artist and progress. Fades away when nothing plays
DeskFit {
    id: root

    property var cfg: ({})
    readonly property var player: Lyrics.player
    readonly property bool present: !!player && !!player.trackTitle
    readonly property color ink: cfg.card && cfg.color === "auto" ? Theme.text : Theme.paint(cfg.color)
    readonly property color mark: cfg.color === "auto" ? Theme.accent : ink
    readonly property string style: cfg.style ?? "card"
    property real pos: 0

    card: !!cfg.card
    tint: ink
    opacity: present ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

    // MprisPlayer.position is computed on read, so poll it while playing
    Timer {
        interval: 1000
        running: root.visible && (root.player?.isPlaying ?? false)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pos = root.player.position
    }

    // Cover beside the text, cover above it, or text alone; a Loader so only the shown layout sizes the widget
    Loader {
        sourceComponent: root.style === "cover" ? stacked : root.style === "text" ? info : side
    }

    Component {
        id: side

        Row {
            spacing: 28

            Cover { size: 168; anchors.verticalCenter: parent.verticalCenter }
            Info { width: 440; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    Component {
        id: stacked

        Column {
            spacing: 22

            Cover { size: 380 }
            Info { width: 380 }
        }
    }

    Component {
        id: info

        Info { width: 440; bar: false }
    }

    component Cover: ClippingRectangle {
        property real size

        width: size
        height: size
        radius: size / 10
        color: Qt.alpha(root.ink, 0.12)

        Image {
            anchors.fill: parent
            source: Art.local(root.player?.trackArtUrl ?? "")
            sourceSize: Qt.size(512, 512)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    component Info: Column {
        property bool bar: true

        spacing: 8

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.player?.trackTitle ?? ""
            color: root.ink
            font.family: Theme.font
            font.pixelSize: 38
            font.weight: Font.Bold
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.player?.trackArtist ?? ""
            color: Qt.alpha(root.ink, 0.7)
            font.family: Theme.font
            font.pixelSize: 28
        }

        Item {
            visible: parent.bar && (root.player?.length ?? 0) > 0
            width: parent.width
            height: 26

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 8
                radius: 4
                color: Qt.alpha(root.ink, 0.2)

                Rectangle {
                    width: parent.width * Math.min(1, root.pos / Math.max(1, root.player?.length ?? 1))
                    height: parent.height
                    radius: 4
                    color: root.mark
                    Behavior on width { NumberAnimation { duration: 1000 } }
                }
            }
        }
    }
}
