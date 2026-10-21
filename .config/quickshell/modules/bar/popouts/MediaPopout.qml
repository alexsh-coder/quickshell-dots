import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services
import qs.modules.musicfx

// Now playing: the cover over a blurred copy of itself, a seek bar and transport controls.
// The tune button swaps them for the music effects
Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property var players: Mpris.players.values
    // Picked by clicking the player name; otherwise whatever is playing
    property MprisPlayer chosen: null
    readonly property MprisPlayer player: (players.includes(chosen) ? chosen : null) ?? players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool hasTrack: !!player && !!player.trackTitle
    readonly property real length: player?.length ?? 0
    readonly property bool seekable: (player?.canSeek ?? false) && (player?.positionSupported ?? false) && length > 0

    // MprisPlayer.position is computed on read, so it is sampled
    property real position: 0

    readonly property bool fx: popouts.fx
    readonly property real headHeight: hasTrack ? content.implicitHeight + 4 : empty.implicitHeight + 8

    implicitWidth: hasTrack ? 440 : fx ? 360 : 280
    implicitHeight: Theme.padTop + (fx ? fxView.implicitHeight : headHeight) + Theme.pad

    function sync() {
        position = player?.position ?? 0;
    }

    function seekTo(frac) {
        if (!seekable)
            return;
        position = frac * length;
        player.position = position;
    }

    function cycle() {
        const i = players.indexOf(player);
        chosen = players[(i + 1) % players.length];
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = String(s % 60).padStart(2, "0");
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + sec : m + ":" + sec;
    }

    onPlayerChanged: sync()
    onHereChanged: sync()

    readonly property bool keyboard: here && popouts.pinned
    onKeyboardChanged: if (keyboard) forceActiveFocus()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            popouts.close();
        else if (event.key === Qt.Key_Space && player?.canTogglePlaying)
            player.togglePlaying();
        else if (event.key === Qt.Key_Left && player?.canGoPrevious)
            player.previous();
        else if (event.key === Qt.Key_Right && player?.canGoNext)
            player.next();
        else
            return;
        event.accepted = true;
    }

    Binding {
        target: root.popouts
        property: "busy"
        value: seek.pressed || fxControls.busy
        when: root.here
    }

    Timer {
        interval: 500
        repeat: true
        running: root.here && (root.player?.isPlaying ?? false)
        onTriggered: root.sync()
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.sync(); }
        function onPostTrackChanged() { root.sync(); }
    }

    // Follows the panel rather than the page, so it fills the panel while it morphs
    Item {
        id: backdrop

        readonly property Item panel: root.popouts.hitbox
        readonly property var levels: root.here && Cava.active ? Cava.downsample(24) : []

        x: (root.width - panel.width) / 2
        width: panel.width
        height: panel.height
        opacity: root.hasTrack && blurCover.ready ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        ClippingRectangle {
            anchors.fill: parent
            color: "transparent"
            radius: root.popouts.corner
            topLeftRadius: 0
            topRightRadius: 0

            // Bigger than the panel, so the blur doesn't darken towards the edges
            Cover {
                id: blurCover
                anchors.fill: parent
                anchors.margins: -60
                url: Art.local(root.player?.trackArtUrl ?? "")
                size: 128
                visible: false
            }

            MultiEffect {
                anchors.fill: blurCover
                source: blurCover
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: 0.15
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.bg, Theme.light ? 0.5 : 0.58)
            }

            // Melts into the bar above
            Rectangle {
                width: parent.width
                height: 64
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.bg }
                    GradientStop { position: 1; color: Qt.alpha(Theme.bg, 0) }
                }
            }

            // Spectrum rising from the bottom edge, bass in the middle
            Row {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3
                opacity: 0.22

                Repeater {
                    model: 48

                    Rectangle {
                        required property int index
                        readonly property real level: backdrop.levels[index < 24 ? 23 - index : index - 24] ?? 0

                        anchors.bottom: parent.bottom
                        width: (backdrop.width - 47 * 3) / 48
                        height: Math.max(2, level * 70)
                        topLeftRadius: width / 2
                        topRightRadius: width / 2
                        color: Theme.accent

                        Behavior on height { NumberAnimation { duration: 60 } }
                    }
                }
            }
        }
    }

    // Player and effects take turns in the same panel, over the same blurred cover
    Item {
        id: playerView

        anchors.fill: parent
        enabled: !root.fx
        opacity: root.fx ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        Column {
            id: content

            x: Theme.pad
            y: Theme.padTop + 4
            width: parent.width - Theme.pad * 2
            spacing: 12
            opacity: root.hasTrack ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }

            Row {
                width: parent.width
                spacing: 16

                ClippingRectangle {
                    id: coverBox

                    width: 112
                    height: 112
                    radius: Theme.radius
                    color: Theme.surface

                    Icon {
                        anchors.centerIn: parent
                        text: "music_note"
                        font.pixelSize: 40
                        color: Theme.subtext
                        opacity: cover.ready ? 0 : 1
                    }

                    Cover {
                        id: cover
                        anchors.fill: parent
                        url: Art.local(root.player?.trackArtUrl ?? "")
                        size: 256
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - coverBox.width - parent.spacing
                    spacing: 4

                    Item {
                        width: parent.width
                        height: 26

                        Row {
                            id: playerName
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            opacity: playerMouse.containsMouse ? 1 : 0.85

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.player?.identity ?? "").toUpperCase()
                                font.pixelSize: 11
                                font.letterSpacing: 1.2
                                color: Theme.subtext
                            }

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.players.length > 1
                                text: "unfold_more"
                                font.pixelSize: 14
                                color: Theme.subtext
                            }
                        }

                        MouseArea {
                            id: playerMouse
                            anchors.fill: playerName
                            anchors.margins: -4
                            enabled: root.players.length > 1
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycle()
                        }

                        FxButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Label {
                        width: parent.width
                        text: root.player?.trackTitle ?? ""
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        text: root.player?.trackArtist ?? ""
                        font.pixelSize: 14
                        color: Theme.subtext
                        elide: Text.ElideRight
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2
                opacity: root.seekable ? 1 : 0.4

                Slider {
                    id: seek

                    property real held: 0

                    width: parent.width
                    enabled: root.seekable
                    value: pressed ? held : root.length > 0 ? root.position / root.length : 0
                    onMoved: v => {
                        held = v;
                        if (!pressed)
                            root.seekTo(v);
                    }
                    onPressedChanged: if (!pressed) root.seekTo(held)
                }

                Item {
                    width: parent.width
                    height: 16

                    Label {
                        text: root.fmt(seek.pressed ? seek.held * root.length : root.position)
                        font.pixelSize: 12
                        color: Theme.subtext
                    }

                    Label {
                        anchors.right: parent.right
                        text: root.fmt(root.length)
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "shuffle"
                    active: root.player?.shuffle ?? false
                    enabled: root.player?.shuffleSupported ?? false
                    onClicked: root.player.shuffle = !root.player.shuffle
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_previous"
                    iconSize: 28
                    plain: true
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player.previous()
                }

                // Circle while paused, squircle while playing, as in M3 Expressive media controls
                Rectangle {
                    id: play

                    readonly property bool playing: root.player?.isPlaying ?? false

                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    height: 52
                    radius: playing ? 16 : 26
                    color: Theme.accent
                    scale: playMouse.pressed ? 0.92 : playMouse.containsMouse ? 1.05 : 1

                    Behavior on radius { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    Icon {
                        anchors.centerIn: parent
                        text: play.playing ? "pause" : "play_arrow"
                        font.pixelSize: 28
                        color: Theme.bg
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player?.canTogglePlaying) root.player.togglePlaying()
                    }
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_next"
                    iconSize: 28
                    plain: true
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player.next()
                }

                CtrlButton {
                    readonly property int loop: root.player?.loopState ?? MprisLoopState.None

                    anchors.verticalCenter: parent.verticalCenter
                    icon: loop === MprisLoopState.Track ? "repeat_one" : "repeat"
                    active: loop !== MprisLoopState.None
                    enabled: root.player?.loopSupported ?? false
                    onClicked: root.player.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist
                        : loop === MprisLoopState.Playlist ? MprisLoopState.Track
                        : MprisLoopState.None
                }
            }
        }

        Column {
            id: empty

            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.padTop + 8
            spacing: 6
            opacity: root.hasTrack ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "music_off"
                font.pixelSize: 30
                color: Theme.subtext
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Nothing playing"
                font.pixelSize: 14
                color: Theme.subtext
            }
        }

        // Same tune button in the corner while nothing plays
        FxButton {
            x: parent.width - Theme.pad - width + 6
            y: Theme.padTop - 4
            opacity: root.hasTrack ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        }
    }

    Column {
        id: fxView

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 14
        enabled: root.fx
        opacity: root.fx ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        Item {
            width: parent.width
            height: 28

            CtrlButton {
                id: back
                x: -6
                anchors.verticalCenter: parent.verticalCenter
                icon: "arrow_back"
                iconSize: 20
                diameter: 32
                plain: true
                onClicked: root.popouts.fx = false
            }

            Label {
                anchors.left: back.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Music effects"
                font.pixelSize: 15
            }

            // What is playing, small, so the cover in the background still has a name
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.45)
                visible: root.hasTrack
                text: root.player?.trackTitle ?? ""
                font.pixelSize: 12
                color: Theme.subtext
                elide: Text.ElideRight
            }
        }

        FxControls {
            id: fxControls
            width: parent.width
        }
    }

    onFxChanged: if (!fx) fxControls.editing = ""

    component FxButton: CtrlButton {
        icon: "tune"
        iconSize: 18
        diameter: 28
        active: root.fx
        onClicked: root.popouts.fx = !root.popouts.fx
    }

    // Two images taking turns, so a new cover fades in over the old one once it has loaded
    component Cover: Item {
        id: coverItem

        property string url
        property int size: 256
        property bool showA: true
        readonly property bool ready: (showA ? picA : picB).status === Image.Ready

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

    component CtrlButton: Item {
        id: btn

        property string icon
        property int iconSize: 22
        property int diameter: 38
        property bool active: false
        // Prev/next are always drawn in the text colour
        property bool plain: false
        signal clicked

        width: diameter
        height: diameter
        opacity: enabled ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(Theme.text, btnMouse.pressed ? 0.14 : 0.08)
            opacity: btnMouse.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        }

        Icon {
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: btn.iconSize
            color: btn.plain ? Theme.text : btn.active ? Theme.accent : Theme.subtext
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
