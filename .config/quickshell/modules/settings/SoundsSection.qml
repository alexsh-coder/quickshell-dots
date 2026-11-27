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
        setting: "sfx"
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
            setting: "sfxPack"
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
            setting: "sfxVolume"
            label: "Volume"
            ValueSlider {
                from: 0; to: 1; step: 0.05
                value: Settings.sfxVolume
                format: v => Math.round(v * 100) + "%"
                onMoved: v => Settings.sfxVolume = v
            }
        }

        SettingRow {
            setting: "sfxMuteMusic"
            label: "Quiet during music"
            hint: "No sounds while a music player is playing"
            Toggle {
                checked: Settings.sfxMuteMusic
                onToggled: Settings.sfxMuteMusic = !checked
            }
        }

        SectionTitle { text: "Play on" }

        Repeater {
            model: Sfx.groups

            Column {
                id: group

                required property var modelData
                readonly property bool on: Sfx.enabled(modelData.id)
                property bool expanded: false

                width: parent.width

                SettingRow {
                    label: group.modelData.label
                    hint: group.modelData.hint
                    changed: !group.on
                    onReset: Sfx.setEnabled(group.modelData.id, true)

                    Row {
                        spacing: 12

                        RoundButton {
                            icon: "play_arrow"
                            enabled: group.on
                            hoverPreview: true
                            onHovered: Sfx.audition(group.modelData.sample)
                            onClicked: Sfx.play(group.modelData.sample, 0)
                        }

                        // Swap single sounds of the group
                        RoundButton {
                            icon: "tune"
                            active: group.expanded
                            enabled: group.on
                            onClicked: group.expanded = !group.expanded
                        }

                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: group.on
                            onToggled: Sfx.setEnabled(group.modelData.id, !checked)
                        }
                    }
                }

                Column {
                    width: parent.width - 24
                    x: 24
                    visible: group.expanded && group.on

                    Repeater {
                        model: group.modelData.events

                        SettingRow {
                            id: ev

                            required property string modelData
                            readonly property var sounds: Sfx.picked(modelData)

                            label: Sfx.eventLabels[modelData] ?? modelData
                            changed: sounds.length > 0
                            onReset: Sfx.pick(modelData, "")

                            Row {
                                spacing: 12

                                RoundButton {
                                    icon: "play_arrow"
                                    hoverPreview: true
                                    onHovered: Sfx.audition(ev.modelData)
                                    onClicked: Sfx.audition(ev.modelData)
                                }

                                Dropdown {
                                    minWidth: 190
                                    hoverPreview: true
                                    onHovered: v => Sfx.audition(ev.modelData, v)
                                    multi: true
                                    current: ev.sounds
                                    model: [{ value: "", label: Sfx.presetName(ev.modelData) ? Sfx.presetName(ev.modelData) + " (preset)" : "Preset sound" }].concat(Sfx.choices.map(c => ({ value: c, label: c.replace(/[_-]/g, " ") })))
                                    onPicked: v => {
                                        const adding = v !== "" && !ev.sounds.includes(v);
                                        Sfx.pick(ev.modelData, v);
                                        if (adding || v === "")
                                            Sfx.audition(ev.modelData, v);
                                    }
                                }
                            }
                        }
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
