import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
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

    readonly property var players: Players.music
    // Picked by clicking the player name; otherwise whatever is playing
    property MprisPlayer chosen: null
    // Players without a track can't be shown, so they are skipped
    readonly property var withTrack: players.filter(p => !!p.trackTitle)
    readonly property MprisPlayer player: (withTrack.includes(chosen) ? chosen : null) ?? withTrack.find(p => p.isPlaying) ?? withTrack[0] ?? players[0] ?? null
    readonly property bool hasTrack: !!player && !!player.trackTitle
    readonly property real length: player?.length ?? 0
    readonly property bool seekable: (player?.canSeek ?? false) && (player?.positionSupported ?? false) && length > 0

    // MprisPlayer.position is computed on read, so it is sampled
    property real position: 0

    readonly property bool fx: popouts.fx
    // The lyrics editor takes the panel, like the effects
    property bool lyrics: false
    property bool pinnedBefore: false
    // Spotify's queue takes the panel too
    property bool queue: false
    readonly property bool canQueue: !!player && player === SpotifyQueue.player
    readonly property real headHeight: hasTrack ? content.implicitHeight + 4 : empty.implicitHeight + 8

    implicitWidth: hasTrack ? 440 : fx ? 360 : 280
    implicitHeight: Theme.padTop + (fx ? fxView.implicitHeight : lyrics ? lyricsView.implicitHeight : queue ? queueView.implicitHeight : headHeight) + Theme.pad

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
        if (!withTrack.length)
            return;
        const i = withTrack.indexOf(player);
        chosen = withTrack[(i + 1) % withTrack.length];
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = String(s % 60).padStart(2, "0");
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + sec : m + ":" + sec;
    }

    onPlayerChanged: sync()
    onHereChanged: {
        sync();
        if (!here) {
            volume.open = false;
            lyrics = false;
            queue = false;
        }
    }
    onHasTrackChanged: if (!hasTrack) lyrics = false
    onCanQueueChanged: if (!canQueue) queue = false
    onQueueChanged: if (queue) {
        lyrics = false;
        popouts.fx = false;
    }

    // Typing and tapping need the keyboard, and the panel must stay while the pointer is away
    onLyricsChanged: {
        if (lyrics) {
            queue = false;
            pinnedBefore = popouts.pinned;
            popouts.fx = false;
            popouts.pinned = true;
        } else {
            if (here && !pinnedBefore)
                popouts.pinned = false;
            if (keyboard)
                forceActiveFocus();
        }
    }

    readonly property bool keyboard: here && popouts.pinned
    onKeyboardChanged: if (keyboard && !lyrics) forceActiveFocus()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            popouts.close();
        else if (event.key === Qt.Key_Space && player?.canTogglePlaying)
            player.togglePlaying();
        else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (event.modifiers & Qt.ShiftModifier) && seekable)
            seekTo(Math.max(0, Math.min(length, position + (event.key === Qt.Key_Left ? -5 : 5))) / length);
        else if (event.key === Qt.Key_Left && (event.modifiers & Qt.ControlModifier) && player?.canGoPrevious)
            player.previous();
        else if (event.key === Qt.Key_Right && (event.modifiers & Qt.ControlModifier) && player?.canGoNext)
            player.next();
        else
            return;
        event.accepted = true;
    }

    Binding {
        target: root.popouts
        property: "busy"
        value: seek.pressed || volSlider.pressed || fxControls.busy
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

            // Melts into the bar above: smoothstep falloff, no visible edge at either end
            Rectangle {
                width: parent.width
                height: 90
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(Theme.bg, 1.000) }
                    GradientStop { position: 0.125; color: Qt.alpha(Theme.bg, 0.957) }
                    GradientStop { position: 0.25; color: Qt.alpha(Theme.bg, 0.844) }
                    GradientStop { position: 0.375; color: Qt.alpha(Theme.bg, 0.684) }
                    GradientStop { position: 0.5; color: Qt.alpha(Theme.bg, 0.500) }
                    GradientStop { position: 0.625; color: Qt.alpha(Theme.bg, 0.316) }
                    GradientStop { position: 0.75; color: Qt.alpha(Theme.bg, 0.156) }
                    GradientStop { position: 0.875; color: Qt.alpha(Theme.bg, 0.043) }
                    GradientStop { position: 1; color: Qt.alpha(Theme.bg, 0.000) }
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
        enabled: !root.fx && !root.lyrics && !root.queue
        opacity: root.fx || root.lyrics || root.queue ? 0 : 1
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
                            onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                            onReleased: if (containsMouse) Sfx.tap("clickPop")
                            anchors.fill: playerName
                            anchors.margins: -4
                            enabled: root.players.length > 1
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycle()
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            CtrlButton {
                                icon: "lyrics"
                                iconSize: 18
                                diameter: 28
                                active: root.lyrics
                                onClicked: root.lyrics = !root.lyrics
                            }

                            FxButton {}
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

                    Item {
                        width: parent.width
                        height: Math.max(artist.implicitHeight, like.visible ? like.height : 0)

                        Label {
                            id: artist
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (like.visible ? like.width + 4 : 0)
                            text: root.player?.trackArtist ?? ""
                            font.pixelSize: 14
                            color: Theme.subtext
                            elide: Text.ElideRight
                        }

                        // Only Spotify's own window can tell and change whether a track is liked
                        CtrlButton {
                            id: like
                            anchors.right: parent.right
                            anchors.rightMargin: -6
                            anchors.verticalCenter: parent.verticalCenter
                            visible: SpotifyLike.known && root.player === SpotifyLike.player
                            // nf-md heart / heart-outline: Material's filled heart rasterizes with holes
                            nerd: SpotifyLike.liked ? "\u{f02d1}" : "\u{f02d5}"
                            iconSize: 20
                            diameter: 30
                            active: SpotifyLike.liked
                            onClicked: SpotifyLike.toggle()
                        }
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

            Item {
                width: parent.width
                height: 52

                Row {
                    anchors.centerIn: parent
                    spacing: 14
                    enabled: !volume.open
                    opacity: volume.open ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

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
                            onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                            onReleased: if (containsMouse) Sfx.tap("clickPop")
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

                // Mirrors the speaker on the right; hidden under the volume slider
                CtrlButton {
                    x: parent.width - width + 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.canQueue
                    icon: "queue_music"
                    active: root.queue
                    enabled: !volume.open
                    opacity: volume.open ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                    onClicked: root.queue = !root.queue
                }

                // Hovering the speaker slides a volume slider out over the transport controls
                Item {
                    id: volume

                    // The player's own volume where it has one, the output's otherwise
                    readonly property bool own: (root.player?.volumeSupported ?? false) && (root.player?.canControl ?? false)
                    readonly property PwNode sink: Pipewire.defaultAudioSink
                    readonly property real level: Math.min(1, (own ? root.player.volume : sink?.audio?.volume) ?? 0)
                    readonly property bool muted: own ? level === 0 : sink?.audio?.muted ?? false
                    readonly property real full: parent.width + 6
                    property real restore: 0.5
                    property bool open: false

                    function set(v) {
                        v = Math.max(0, Math.min(1, v));
                        if (own) {
                            root.player.volume = v;
                        } else if (sink?.audio) {
                            sink.audio.volume = v;
                            if (v > 0 && sink.audio.muted)
                                sink.audio.muted = false;
                        }
                    }

                    function toggleMute() {
                        if (!own) {
                            if (sink?.audio)
                                sink.audio.muted = !sink.audio.muted;
                        } else if (level > 0) {
                            restore = level;
                            set(0);
                        } else {
                            set(restore);
                        }
                    }

                    x: -6
                    width: open ? full : speaker.width
                    height: parent.height

                    PwObjectTracker {
                        objects: [volume.sink]
                    }

                    HoverHandler {
                        id: volHover
                        onHoveredChanged: if (hovered) volume.open = true; else closer.restart()
                    }

                    Timer {
                        id: closer
                        interval: 500
                        onTriggered: if (!volHover.hovered && !volSlider.pressed) volume.open = false
                    }

                    CtrlButton {
                        id: speaker
                        anchors.verticalCenter: parent.verticalCenter
                        icon: volume.muted || volume.level === 0 ? "volume_off"
                            : volume.level < 0.34 ? "volume_mute"
                            : volume.level < 0.67 ? "volume_down"
                            : "volume_up"
                        active: volume.open
                        enabled: volume.own || !!volume.sink
                        onClicked: volume.toggleMute()
                    }

                    MouseArea {
                        anchors.fill: speaker
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => volume.set(volume.level + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                    }

                    Item {
                        anchors.left: speaker.right
                        anchors.leftMargin: 8
                        width: volume.open ? volume.full - speaker.width - 8 : 0
                        height: parent.height
                        clip: true
                        opacity: volume.open ? 1 : 0
                        Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                        Slider {
                            id: volSlider

                            property real held: 0

                            anchors.verticalCenter: parent.verticalCenter
                            width: volume.full - speaker.width - 8 - 44
                            value: pressed ? held : volume.level
                            dim: volume.muted
                            onMoved: v => {
                                held = v;
                                volume.set(v);
                            }
                            onPressedChanged: if (!pressed) closer.restart()
                        }

                        Label {
                            x: volSlider.width + 8
                            width: 36
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: volume.muted && !volume.own ? "Muted" : Math.round(volume.level * 100) + "%"
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }
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

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "Music effects"
                font.pixelSize: 15
            }

            // What is playing, small, so the cover in the background still has a name
            Label {
                anchors.right: back.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.45)
                visible: root.hasTrack
                text: root.player?.trackTitle ?? ""
                font.pixelSize: 12
                color: Theme.subtext
                elide: Text.ElideRight
            }

            // On the right, where the tune button that opened this view sits
            CtrlButton {
                id: back
                x: parent.width - width + 6
                anchors.verticalCenter: parent.verticalCenter
                icon: "arrow_back"
                iconSize: 20
                diameter: 32
                plain: true
                onClicked: root.popouts.fx = false
            }
        }

        // Scrolls once it's taller than the screen below the bar
        Flickable {
            id: fxFlick

            width: parent.width
            height: Math.min(fxControls.implicitHeight, root.popouts.height - Theme.barHeight - Theme.padTop - Theme.pad - 28 - parent.spacing - 16)
            contentHeight: fxControls.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            HoverHandler { id: fxHover }

            // Thin draggable bar in the right margin, only while the pointer is over the list
            QQC.ScrollBar.vertical: QQC.ScrollBar {
                id: fxBar

                parent: root
                x: root.width - width - 4
                y: fxView.y + fxFlick.y
                height: fxFlick.height
                width: 8
                padding: 0
                policy: fxFlick.contentHeight > fxFlick.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
                visible: root.fx
                opacity: fxHover.hovered || hovered || pressed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                background: null
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: width / 2
                    x: (fxBar.width - width) / 2
                    width: fxBar.hovered || fxBar.pressed ? 6 : 4
                    color: fxBar.pressed ? Theme.accent : Qt.alpha(Theme.subtext, fxBar.hovered ? 0.7 : 0.4)
                    Behavior on width { NumberAnimation { duration: 120 } }
                }
            }

            FxControls {
                id: fxControls
                width: parent.width
                onCustomize: {
                    root.popouts.close();
                    Desk.editing = true;
                }
            }
        }
    }

    LyricsEditor {
        id: lyricsView

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        player: root.player
        active: root.lyrics
        enabled: root.lyrics
        opacity: root.lyrics ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        onBack: root.lyrics = false
    }

    QueueView {
        id: queueView

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        active: root.queue && root.here
        enabled: root.queue
        opacity: root.queue ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        onBack: root.queue = false
        onTyping: popouts.pinned = true
    }

    onFxChanged: {
        if (!fx)
            fxControls.editing = "";
        else {
            lyrics = false;
            queue = false;
        }
    }

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
}
