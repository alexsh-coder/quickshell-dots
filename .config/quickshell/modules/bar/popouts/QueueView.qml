import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

// Spotify's upcoming tracks; clicking one plays it
Item {
    id: root

    property bool active: false
    signal back

    readonly property int rowHeight: 48

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

            Label {
                id: heading
                anchors.verticalCenter: parent.verticalCenter
                text: "Queue"
                font.pixelSize: 15
            }

            Label {
                anchors.left: heading.right
                anchors.leftMargin: 10
                anchors.right: actions.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: SpotifyQueue.context ? "Next from " + SpotifyQueue.context : ""
                font.pixelSize: 12
                color: Theme.subtext
                elide: Text.ElideRight
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
            height: root.rowHeight * 6

            Label {
                anchors.centerIn: parent
                visible: !SpotifyQueue.tracks.length && !SpotifyQueue.loading
                text: SpotifyQueue.failed ? "Can't reach Spotify" : "Nothing up next"
                font.pixelSize: 13
                color: Theme.subtext
            }

            ListView {
                id: list

                anchors.fill: parent
                model: SpotifyQueue.tracks
                clip: true
                boundsBehavior: Flickable.StopAtBounds

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

                    required property int index
                    required property var modelData

                    width: list.width
                    height: root.rowHeight

                    // Rows are created as they scroll into view, so covers download only when needed
                    Component.onCompleted: Art.fetch(modelData.art ?? "")

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Qt.alpha(Theme.text, rowMouse.pressed ? 0.12 : 0.07)
                        opacity: rowMouse.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }

                    Label {
                        id: number
                        x: 2
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        visible: !rowMouse.containsMouse
                        text: row.index + 1
                        font.pixelSize: 12
                        color: Theme.subtext
                    }

                    Icon {
                        anchors.centerIn: number
                        anchors.horizontalCenterOffset: 1
                        visible: rowMouse.containsMouse
                        text: "play_arrow"
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
                            source: Art.local(row.modelData.art ?? "")
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

                        Label {
                            width: parent.width
                            text: row.modelData.title
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: row.modelData.artists
                            font.pixelSize: 12
                            color: Theme.subtext
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SpotifyQueue.play(row.index)
                    }
                }
            }
        }
    }
}
