import QtQuick
import qs.config
import qs.components
import qs.services

// Cursor themes to pick from, each with a strip of its arrow, hand and text cursor:
// model is [{ value, label, preview }], current the value picked
Flow {
    id: root

    property var model: []
    property var current
    signal picked(var value)

    spacing: 6
    // Tiles stretch so each row fills the width
    readonly property int columns: Math.max(1, Math.floor((width + spacing) / (132 + spacing)))
    readonly property real tileWidth: (width - spacing * (columns - 1)) / columns

    Repeater {
        model: root.model

        Rectangle {
            id: tile

            required property var modelData
            readonly property bool on: root.current === modelData.value

            width: root.tileWidth
            height: 74
            radius: 10
            color: on ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.22)) : area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.1)) : Theme.surface
            border.width: on ? 2 : 0
            border.color: Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: 120
                height: 40
                source: tile.modelData.preview ?? ""
                sourceSize: Qt.size(168, 56)
                fillMode: Image.PreserveAspectFit
                cache: false
                smooth: true
                mipmap: true
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                text: tile.modelData.label
                font.pixelSize: 12
                color: tile.on ? Theme.accent : Theme.text
            }

            MouseArea {
                id: area
                onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                onReleased: if (containsMouse) Sfx.tap("click")

                // Flipped and back after a cursor theme change, so the new theme shows under the pointer
                property bool kicked: false

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: kicked ? Qt.ArrowCursor : Qt.PointingHandCursor

                Connections {
                    target: Cursor
                    function onApplied() {
                        if (area.containsMouse) {
                            area.kicked = true;
                            area.kicked = false;
                        }
                    }
                }
                onClicked: root.picked(tile.modelData.value)
            }
        }
    }
}
