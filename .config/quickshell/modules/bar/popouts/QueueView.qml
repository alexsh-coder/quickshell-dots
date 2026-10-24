import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

// Spotify's tracks around the playing one; clicking one plays it
Item {
    id: root

    property bool active: false
    signal back
    // Asks the panel for the keyboard, the search field needs it
    signal typing

    readonly property string query: search.text.trim().toLowerCase()
    // The library list replaces the tracks while picking what to play
    property bool picking: false
    readonly property bool liked: SpotifyQueue.context === "Liked Songs"
    readonly property var shownLibrary: SpotifyQueue.library.filter(l => !query || l.name.toLowerCase().includes(query))

    onPickingChanged: {
        search.text = "";
        if (picking)
            SpotifyQueue.loadLibrary();
    }
    // Indices into SpotifyQueue.tracks that match the search
    readonly property var shown: SpotifyQueue.tracks.map((t, i) => i).filter(i => {
        const t = SpotifyQueue.tracks[i];
        return !query || (t.title + " " + t.artists).toLowerCase().includes(query);
    })

    onActiveChanged: if (!active) {
        search.text = "";
        picking = false;
    }

    readonly property int rowHeight: 48
    property real rows: 6

    implicitHeight: column.implicitHeight

    Binding {
        target: SpotifyQueue
        property: "watched"
        value: root.active
    }

    Column {
        id: column

        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 28

            CtrlButton {
                id: heading
                x: -6
                anchors.verticalCenter: parent.verticalCenter
                icon: root.picking || root.liked ? "favorite" : "queue_music"
                iconSize: 20
                diameter: 32
                active: true
                fill: root.liked && !root.picking ? 1 : 0
                onClicked: root.picking = !root.picking
            }

            Item {
                anchors.left: heading.right
                anchors.leftMargin: 4
                anchors.right: actions.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: 28

                Icon {
                    id: searchIcon
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    font.pixelSize: 15
                    color: Theme.subtext
                }

                TextInput {
                    id: search

                    anchors.left: searchIcon.right
                    anchors.leftMargin: 6
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.accent, 0.4)
                    clip: true

                    onTextChanged: list.positionViewAtBeginning()
                    onAccepted: {
                        if (root.picking && root.shownLibrary.length) {
                            SpotifyQueue.open(root.shownLibrary[0].uri);
                            root.picking = false;
                        } else if (!root.picking && root.shown.length) {
                            SpotifyQueue.play(root.shown[0]);
                        }
                    }
                    Keys.onEscapePressed: event => {
                        if (text) {
                            text = "";
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }

                    Label {
                        visible: !search.text
                        text: root.picking ? "Library" : "Search"
                        font.pixelSize: 13
                        color: Theme.subtext
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onPressed: mouse => {
                        root.typing();
                        search.forceActiveFocus();
                        mouse.accepted = false;
                    }
                }
            }

            Row {
                id: actions

                x: parent.width - width + 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "progress_activity"
                    font.pixelSize: 16
                    color: Theme.subtext
                    opacity: SpotifyQueue.loading ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                    RotationAnimation on rotation {
                        running: SpotifyQueue.loading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "arrow_back"
                    iconSize: 20
                    diameter: 32
                    plain: true
                    onClicked: root.back()
                }
            }
        }

        Item {
            width: parent.width
            height: root.rowHeight * root.rows

            Label {
                anchors.centerIn: parent
                visible: !root.picking && !root.shown.length && !SpotifyQueue.loading
                text: root.query ? "No matches" : SpotifyQueue.failed ? "Can't reach Spotify" : "Nothing here"
                font.pixelSize: 13
                color: Theme.subtext
            }

            ListView {
                id: libraryList

                anchors.fill: parent
                visible: root.picking
                model: root.shownLibrary
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: entry

                    required property var modelData
                    readonly property bool playing: modelData.name === SpotifyQueue.context

                    width: libraryList.width
                    height: root.rowHeight

                    Component.onCompleted: Art.fetch(modelData.art)

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: entry.playing ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.text, entryMouse.pressed ? 0.12 : 0.07)
                        opacity: entry.playing || entryMouse.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }

                    ClippingRectangle {
                        id: cover
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: entry.modelData.kind === "artist" ? 18 : 6
                        color: entry.modelData.kind === "liked" ? Qt.alpha(Theme.accent, 0.18) : Theme.surface

                        Icon {
                            anchors.centerIn: parent
                            visible: entry.modelData.kind === "liked"
                            text: "favorite"
                            font.pixelSize: 18
                            color: Theme.accent
                        }

                        Image {
                            anchors.fill: parent
                            visible: !!entry.modelData.art
                            source: Art.local(entry.modelData.art)
                            sourceSize.width: 96
                            sourceSize.height: 96
                            fillMode: Image.PreserveAspectCrop
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                        }
                    }

                    Column {
                        anchors.left: cover.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Label {
                            width: parent.width
                            text: entry.modelData.name
                            font.pixelSize: 14
                            color: entry.playing ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: ({ liked: "Playlist", playlist: "Playlist", album: "Album", artist: "Artist" })[entry.modelData.kind] ?? ""
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            SpotifyQueue.open(entry.modelData.uri);
                            root.picking = false;
                        }
                    }
                }
            }

            ListView {
                id: list

                anchors.fill: parent
                visible: !root.picking
                model: root.shown
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Opens with the playing track in the middle
                function reveal() {
                    if (root.active && !root.query && SpotifyQueue.current >= 0)
                        positionViewAtIndex(SpotifyQueue.current, ListView.Center);
                }

                onCountChanged: reveal()
                Connections {
                    target: root
                    function onActiveChanged() { list.reveal(); }
                }

                HoverHandler {
                    id: listHover
                }

                // Same as the settings window: a thin draggable bar while the pointer is near the right edge
                QQC.ScrollBar.vertical: QQC.ScrollBar {
                    id: vbar

                    readonly property bool near: listHover.hovered && listHover.point.position.x > list.width - 56

                    parent: list.parent
                    x: list.x + list.width - width + 4
                    y: list.y + 4
                    height: list.height - 8
                    width: 8
                    padding: 0
                    policy: list.contentHeight > list.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
                    opacity: near || hovered || pressed ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                    background: null
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: width / 2
                        x: (vbar.width - width) / 2
                        width: vbar.hovered || vbar.pressed ? 6 : 4
                        color: vbar.pressed ? Theme.accent : Qt.alpha(Theme.subtext, vbar.hovered ? 0.7 : 0.4)
                        Behavior on width {
                            NumberAnimation { duration: 120 }
                        }
                    }
                }

                delegate: Item {
                    id: row

                    required property int modelData
                    readonly property int index: modelData
                    readonly property var track: SpotifyQueue.tracks[index] ?? {}
                    readonly property bool playing: index === SpotifyQueue.current
                    readonly property bool played: index < SpotifyQueue.current

                    width: list.width
                    height: root.rowHeight

                    // Rows are created as they scroll into view, so covers download only when needed
                    Component.onCompleted: Art.fetch(track.art ?? "")

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: row.playing ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.text, rowMouse.pressed ? 0.12 : 0.07)
                        opacity: row.playing || rowMouse.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }

                    Label {
                        id: number
                        x: 2
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        visible: !row.playing && !rowMouse.containsMouse
                        text: row.index + 1
                        font.pixelSize: 12
                        color: Theme.subtext
                    }

                    Icon {
                        anchors.centerIn: number
                        anchors.horizontalCenterOffset: 1
                        visible: row.playing || rowMouse.containsMouse
                        text: row.playing ? "graphic_eq" : "play_arrow"
                        font.pixelSize: 18
                        color: Theme.accent
                    }

                    ClippingRectangle {
                        id: art
                        anchors.left: number.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 6
                        color: Theme.surface

                        Image {
                            anchors.fill: parent
                            source: Art.local(row.track.art ?? "")
                            sourceSize.width: 96
                            sourceSize.height: 96
                            fillMode: Image.PreserveAspectCrop
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                        }
                    }

                    Column {
                        anchors.left: art.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        opacity: row.played ? 0.55 : 1

                        Label {
                            width: parent.width
                            text: row.track.title
                            font.pixelSize: 14
                            color: row.playing ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: row.track.artists
                            font.pixelSize: 12
                            color: Theme.subtext
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.playing ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: SpotifyQueue.play(row.index)
                    }
                }
            }
        }
    }
}
