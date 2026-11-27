import QtQuick
import qs.config
import qs.components
import qs.services

// Interface sounds: the pack, how loud, and which kinds play at all
Column {
    id: root

    property bool shown: false

    spacing: 6

    SectionTitle { text: "Sounds" }

    SettingRow {
        label: "Interface sounds"
        hint: "Everything below; the pack is Kenney's, CC0"
        Toggle {
            checked: Settings.sfx
            onToggled: Settings.sfx = !checked
        }
    }

    Column {
        width: parent.width
        spacing: root.spacing
        enabled: Settings.sfx

        SettingRow {
            label: "Sound pack"
            Dropdown {
                current: Sfx.pack
                model: Sfx.packs
                onPicked: v => {
                    Settings.sfxPack = v;
                    preview.restart();
                }
            }
        }

        SettingRow {
            label: "Volume"
            ValueSlider {
                from: 0; to: 1; step: 0.05
                value: Settings.sfxVolume
                format: v => Math.round(v * 100) + "%"
                onMoved: v => Settings.sfxVolume = v
            }
        }

        SectionTitle { text: "Play on" }

        Repeater {
            model: Sfx.groups

            SettingRow {
                id: row

                required property var modelData
                readonly property bool on: Sfx.enabled(modelData.id)

                label: modelData.label
                hint: modelData.hint

                Row {
                    spacing: 12

                    // Hear it before deciding
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 15
                        enabled: row.on
                        opacity: enabled ? 1 : 0.4
                        color: playArea.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
                        Behavior on color { ColorAnimation { duration: Theme.anim } }

                        Icon {
                            anchors.centerIn: parent
                            text: "play_arrow"
                            font.pixelSize: 18
                        }

                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                            onClicked: Sfx.play(row.modelData.sample, 0)
                        }
                    }

                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: row.on
                        onToggled: Sfx.setEnabled(row.modelData.id, !checked)
                    }
                }
            }
        }
    }

    // The picked pack's notification, once its sounds have loaded
    Timer {
        id: preview
        interval: 250
        onTriggered: Sfx.play("notify", 0)
    }
}
