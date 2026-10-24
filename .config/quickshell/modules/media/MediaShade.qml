import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts

// Super+Shift+M: now playing on a drop shade. The blurred cover fills the shade,
// the visualizer runs along its bottom edge, the current lyric line sits under the title
Scope {
    id: root

    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool hasTrack: !!player && !!player.trackTitle
    readonly property real length: player?.length ?? 0
    readonly property bool seekable: (player?.canSeek ?? false) && (player?.positionSupported ?? false) && length > 0
    readonly property string art: Art.local(player?.trackArtUrl ?? "")
    readonly property string lyric: Lyrics.player === player ? (Lyrics.lines[Lyrics.index]?.text ?? "") : ""

    // Black and white along with a B&W, Invertible or bw-mode wallpaper
    property real gray: Accent.mono ? 1 : 0
    Behavior on gray { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    // MprisPlayer.position is computed on read, so it is sampled
    property real position: 0

    // Spotify's queue replaces the player in the middle of the shade
    property bool queue: false
    readonly property bool canQueue: !!player && player === SpotifyQueue.player
    onCanQueueChanged: if (!canQueue) queue = false

    function sync() {
        position = player?.position ?? 0;
    }

    function seekTo(frac) {
        if (!seekable)
            return;
        position = Math.max(0, Math.min(1, frac)) * length;
        player.position = position;
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = String(s % 60).padStart(2, "0");
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + sec : m + ":" + sec;
    }

    onPlayerChanged: sync()

    IpcHandler {
        target: "mediashade"

        function toggle(): void {
            root.sync();
            drop.toggle();
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: drop.open && (root.player?.isPlaying ?? false)
        onTriggered: root.sync()
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.sync(); }
        function onPostTrackChanged() { root.sync(); }
    }

    DropShade {
        id: drop

        namespace: "mediashade"
        onOpenChanged: if (!open) root.queue = false

        // Blurred cover over the whole shade; bigger than it, so the blur doesn't darken the edges
        Item {
            anchors.fill: parent
            opacity: root.hasTrack ? 0.55 : 0
            layer.enabled: root.gray > 0
            layer.effect: MultiEffect { saturation: -root.gray }
            Behavior on opacity { NumberAnimation { duration: 600 } }

            Cover {
                id: backdrop
                anchors.fill: parent
                anchors.margins: -120
                url: root.art
                size: 128
                visible: false
            }

            MultiEffect {
                anchors.fill: backdrop
                source: backdrop
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: 0.2
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.bg, 0.55)
            }
        }

        // Visualizer standing on the bottom edge
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            opacity: drop.landed && Cava.active ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: 500 } }

            Repeater {
                // Bars exist only while the shade is up: hidden, they'd still animate every cava frame
                model: drop.visible ? Cava.bars : 0

                Rectangle {
                    required property int index

                    anchors.bottom: parent.bottom
                    width: (drop.width - 6 * (Cava.bars - 1)) / Cava.bars
                    height: 4 + Math.min(1, Cava.values[index] ?? 0) * 140
                    topLeftRadius: 4
                    topRightRadius: 4
                    color: Theme.accent
                    Behavior on height { NumberAnimation { duration: 90 } }
                }
            }
        }

        Item {
            id: keys

            anchors.fill: parent
            focus: true

            // Key codes, not text, so both EN and RU layouts work
            Keys.onPressed: event => {
                const p = root.player;
                const shift = event.modifiers & Qt.ShiftModifier;
                if (event.key === Qt.Key_Escape && root.queue)
                    root.queue = false;
                else if (event.key === Qt.Key_Escape)
                    drop.hide();
                else if (event.key === Qt.Key_Space && p?.canTogglePlaying)
                    p.togglePlaying();
                else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && shift && root.seekable)
                    root.seekTo((root.position + (event.key === Qt.Key_Left ? -5 : 5)) / root.length);
                else if (event.key === Qt.Key_Left && p?.canGoPrevious)
                    p.previous();
                else if (event.key === Qt.Key_Right && p?.canGoNext)
                    p.next();
                else
                    return;
                event.accepted = true;
            }
        }

        // Centered in the space below the bar
        Column {
            id: main

            anchors.centerIn: parent
            anchors.verticalCenterOffset: Theme.barHeight / 2
            spacing: 0
            visible: root.hasTrack && opacity > 0
            enabled: !root.queue
            opacity: root.queue ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // The cover drops in a beat after the shade lands
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340
                height: 340
                scale: drop.landed && drop.open ? 1 : 0.6
                opacity: drop.landed && drop.open ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                Behavior on opacity { NumberAnimation { duration: 300 } }

                RectangularShadow {
                    anchors.fill: parent
                    radius: 28
                    blur: 60
                    spread: 4
                    color: Theme.accent
                    opacity: (root.player?.isPlaying ?? false) ? 0.35 + Cava.bass * 0.3 : 0.12
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                Cover {
                    id: cover
                    anchors.fill: parent
                    url: root.art
                    size: 512
                    visible: false
                }

                Rectangle {
                    id: coverMask
                    anchors.fill: parent
                    radius: 28
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: parent
                    source: cover
                    maskEnabled: true
                    maskSource: coverMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                    // Grayed in its own pass, like the ring's cover
                    layer.enabled: root.gray > 0
                    layer.effect: MultiEffect { saturation: -root.gray }
                }
            }

            Item { width: 1; height: 36 }

            Pop {
                order: 1
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, 760)
                    text: root.player?.trackTitle ?? ""
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: Theme.text
                }
            }

            Item { width: 1; height: 6 }

            Pop {
                order: 1
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, 760)
                    text: root.player?.trackArtist ?? ""
                    font.pixelSize: 18
                    elide: Text.ElideRight
                    color: Theme.subtext
                }
            }

            // Current lyric line, crossfading as it changes
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 760
                height: 52

                Label {
                    id: lyricLabel
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: 20
                    color: Theme.accent
                    opacity: drop.landed ? 1 : 0
                    text: root.lyric

                    Behavior on text {
                        SequentialAnimation {
                            NumberAnimation { target: lyricLabel; property: "opacity"; to: 0; duration: 140 }
                            PropertyAction {}
                            NumberAnimation { target: lyricLabel; property: "opacity"; to: 1; duration: 220 }
                        }
                    }
                }
            }

            Pop {
                order: 2
                width: 560
                height: 40

                Item {
                    id: bar

                    width: parent.width
                    height: 16
                    readonly property real frac: root.length > 0 ? Math.min(1, root.position / root.length) : 0

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: seekArea.containsMouse || seekArea.pressed ? 8 : 6
                        radius: height / 2
                        color: Qt.alpha(Theme.text, 0.15)
                        Behavior on height { NumberAnimation { duration: Theme.anim } }

                        Rectangle {
                            width: Math.max(parent.height, parent.width * bar.frac)
                            height: parent.height
                            radius: height / 2
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        id: seekArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        enabled: root.seekable
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => root.seekTo((mouse.x - 6) / bar.width)
                        onPositionChanged: mouse => { if (pressed) root.seekTo((mouse.x - 6) / bar.width); }
                    }
                }

                Label {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    text: root.fmt(root.position)
                    font.pixelSize: 13
                    color: Theme.subtext
                }

                Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: root.fmt(root.length)
                    font.pixelSize: 13
                    color: Theme.subtext
                }
            }

            Item { width: 1; height: 28 }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28

                RoundButton {
                    order: 3
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 56
                    nerd: SpotifyLike.liked ? "\u{f02d1}" : "\u{f02d5}"
                    iconSize: 24
                    on: SpotifyLike.liked
                    enabled: SpotifyLike.known && root.player === SpotifyLike.player
                    onClicked: SpotifyLike.toggle()
                }

                RoundButton {
                    order: 4
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 76
                    icon: "skip_previous"
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player.previous()
                }

                RoundButton {
                    order: 5
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 104
                    icon: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                    iconSize: 52
                    filled: true
                    enabled: root.player?.canTogglePlaying ?? false
                    onClicked: root.player.togglePlaying()
                }

                RoundButton {
                    order: 6
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 76
                    icon: "skip_next"
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player.next()
                }

                RoundButton {
                    order: 7
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 56
                    icon: "queue_music"
                    iconSize: 24
                    on: root.queue
                    enabled: root.canQueue
                    onClicked: root.queue = !root.queue
                }
            }
        }

        QueueView {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Theme.barHeight / 2
            width: 560
            scale: 1.4
            rows: 7
            active: root.queue && drop.open
            enabled: root.queue
            opacity: root.queue ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            onBack: {
                root.queue = false;
                keys.forceActiveFocus();
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Theme.barHeight / 2
            spacing: 16
            visible: !root.hasTrack
            opacity: drop.landed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "music_off"
                font.pixelSize: 96
                fill: 0
                weight: 300
                color: Theme.subtext
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Nothing playing"
                font.pixelSize: 20
                color: Theme.subtext
            }
        }
    }

    // Pops in after the shade lands, staggered by order
    component Pop: Item {
        property int order: 0

        anchors.horizontalCenter: parent?.horizontalCenter
        width: 760
        height: childrenRect.height
        opacity: drop.landed && drop.open ? 1 : 0
        transform: Translate {
            y: drop.landed && drop.open ? 0 : 24
            Behavior on y {
                SequentialAnimation {
                    PauseAnimation { duration: drop.open ? 60 + order * 50 : 0 }
                    NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }
            }
        }
        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: drop.open ? 60 + order * 50 : 0 }
                NumberAnimation { duration: 260 }
            }
        }
    }

    // Round transport button with the power menu's soft hover glow
    component RoundButton: Item {
        id: rb

        property int order: 0
        property int diameter: 76
        property string icon: ""
        property string nerd: ""
        property int iconSize: 36
        property bool filled: false
        property bool on: false
        signal clicked

        width: diameter
        height: diameter
        opacity: !enabled ? 0.35 : drop.landed && drop.open ? 1 : 0
        scale: drop.landed && drop.open ? (area.pressed ? 0.92 : area.containsMouse ? 1.06 : 1) : 0.5
        Behavior on opacity { NumberAnimation { duration: 260 } }
        Behavior on scale { NumberAnimation { duration: 420 + rb.order * 40; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        RectangularShadow {
            anchors.fill: parent
            radius: width / 2
            blur: 32
            spread: 2
            color: Theme.accent
            opacity: area.containsMouse && rb.enabled ? 0.45 : rb.filled ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: rb.filled ? Theme.accent : area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Qt.alpha(Theme.surface, 0.8)
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        Icon {
            anchors.centerIn: parent
            visible: rb.icon !== ""
            text: rb.icon
            font.pixelSize: rb.iconSize
            fill: 1
            weight: 500
            color: rb.filled ? Theme.bg : Theme.text
        }

        NerdIcon {
            anchors.centerIn: parent
            visible: rb.nerd !== ""
            text: rb.nerd
            font.pixelSize: rb.iconSize
            color: rb.on ? Theme.accent : Theme.text
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: rb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    // Two images taking turns, so a new cover fades in over the old one once it has loaded
    component Cover: Item {
        id: coverItem

        property string url
        property int size: 256
        property bool showA: true

        function load() {
            const back = showA ? picB : picA;
            if (back.source.toString() === url && back.status === Image.Ready)
                showA = !showA;
            else
                back.source = url;
        }

        onUrlChanged: load()
        Component.onCompleted: picA.source = url

        Pic {
            id: picA
            size: coverItem.size
            opacity: coverItem.showA ? 1 : 0
            onStatusChanged: if (status === Image.Ready && !coverItem.showA && source.toString() === coverItem.url) coverItem.showA = true
        }

        Pic {
            id: picB
            size: coverItem.size
            opacity: coverItem.showA ? 0 : 1
            onStatusChanged: if (status === Image.Ready && coverItem.showA && source.toString() === coverItem.url) coverItem.showA = false
        }
    }

    component Pic: Image {
        property int size

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: size
        sourceSize.height: size
        smooth: true
        mipmap: true
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }
}
