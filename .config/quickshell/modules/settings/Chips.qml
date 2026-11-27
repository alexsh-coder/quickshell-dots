import QtQuick
import qs.config
import qs.components
import qs.services

// One of a few choices: model is [{ value, label }], current the value picked.
// Lines up in one row, wrapping once wider than maxWidth
Flow {
    id: root

    property var model: []
    property var current
    property real maxWidth: 420
    signal picked(var value)

    width: Math.min(maxWidth, measure.implicitWidth)
    spacing: 6

    Row {
        id: measure
        visible: false
        spacing: root.spacing
        Repeater {
            model: root.model
            Label {
                required property var modelData
                text: modelData.label
                font.pixelSize: 13
                width: implicitWidth + 24
            }
        }
    }

    Repeater {
        model: root.model

        Rectangle {
            id: chip

            required property var modelData
            readonly property bool on: root.current === modelData.value

            width: label.implicitWidth + 24
            height: 30
            radius: height / 2
            color: on ? Theme.accent : area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            Label {
                id: label
                anchors.centerIn: parent
                text: chip.modelData.label
                font.pixelSize: 13
                color: chip.on ? Theme.bg : Theme.text
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }

            MouseArea {
                id: area
                onContainsMouseChanged: if (containsMouse) Sfx.play("hover")

                // Flipped and back after a cursor theme change, so the new theme shows under the pointer
                property bool kicked: false

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: kicked ? Qt.ArrowCursor : Qt.PointingHandCursor

                Connections {
                    target: Cursor
                    function onApplied() {
                        if (area.containsMouse) {
                            // Both shapes go out in one batch, so Hyprland never draws the arrow
                            area.kicked = true;
                            area.kicked = false;
                        }
                    }
                }
                onClicked: {
                    Sfx.play("click");
                    root.picked(chip.modelData.value);
                }
            }
        }
    }
}
