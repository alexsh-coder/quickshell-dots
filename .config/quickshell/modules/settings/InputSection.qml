import QtQuick
import qs.config
import qs.components
import qs.services

// Keyboard, mouse, touchpad and cursor
Column {
    id: root

    property bool shown: false

    spacing: 6

    SectionTitle { text: "Keyboard" }

    SettingRow {
        label: "Repeat rate"
        hint: "Characters per second while a key is held"
        ValueSlider {
            from: 10; to: 60; step: 1
            value: Settings.get("repeat_rate")
            format: v => v + "/s"
            onMoved: v => Settings.set("repeat_rate", v)
        }
    }

    SettingRow {
        label: "Repeat delay"
        hint: "How long to hold a key before it repeats"
        ValueSlider {
            from: 150; to: 1000; step: 25
            value: Settings.get("repeat_delay")
            format: v => v + " ms"
            onMoved: v => Settings.set("repeat_delay", v)
        }
    }

    SectionTitle { text: "Mouse and touchpad" }

    SettingRow {
        label: "Pointer speed"
        ValueSlider {
            from: -1; to: 1; step: 0.05
            value: Settings.get("mouse_sensitivity")
            format: v => (v > 0 ? "+" : "") + v.toFixed(2)
            onMoved: v => Settings.set("mouse_sensitivity", v)
        }
    }

    SettingRow {
        label: "Natural scrolling"
        hint: "Content follows the fingers on the touchpad"
        Toggle {
            checked: Settings.get("natural_scroll")
            onToggled: Settings.set("natural_scroll", !checked)
        }
    }

    SettingRow {
        label: "Tap to click"
        Toggle {
            checked: Settings.get("tap_to_click")
            onToggled: Settings.set("tap_to_click", !checked)
        }
    }

    SectionTitle { text: "Cursor" }

    SettingRow {
        label: "Cursor theme"
        hint: "Apps loading the theme themselves (XWayland) pick it up after a restart"
    }

    CursorTiles {
        width: root.width
        current: Cursor.current?.family
        model: Cursor.families.map(f => ({ value: f, label: f, preview: f === Cursor.current?.family ? Cursor.shownPreview : Cursor.previews[Cursor.themeFor(f, "", "")?.name] }))
        onPicked: v => Cursor.pick(v, Cursor.current?.style, Cursor.current?.color)
    }

    Item { width: 1; height: 6 }

    SettingRow {
        id: styleRow
        readonly property var styles: [...new Set(Cursor.siblings.map(t => t.style))]
        // Styles that look apart (the anime characters) get previews too
        readonly property bool tiles: Cursor.current?.family === "Anime"
        visible: styles.length > 1
        label: "Style"
        Chips {
            visible: !styleRow.tiles
            current: Cursor.current?.style
            model: styleRow.styles.map(v => ({ value: v, label: v }))
            onPicked: v => Cursor.pick(Cursor.current.family, v, Cursor.current.color)
        }
    }

    CursorTiles {
        visible: styleRow.visible && styleRow.tiles
        width: root.width
        current: Cursor.current?.style
        model: styleRow.styles.map(v => ({ value: v, label: v, preview: v === Cursor.current?.style ? Cursor.shownPreview : Cursor.previews[Cursor.themeFor(Cursor.current.family, v, "")?.name] }))
        onPicked: v => Cursor.pick(Cursor.current.family, v, Cursor.current.color)
    }

    // Recolorable themes get black, white or the accent; the rest keep their own color variants
    SettingRow {
        id: colorRow
        readonly property var colors: Cursor.recolorable ? ["Black", "White", "Accent"] : [...new Set(Cursor.siblings.filter(t => t.style === Cursor.current?.style).map(t => t.color))].filter(c => c)
        visible: colors.length > 1 || Cursor.selfColored
        label: "Color"
        hint: Cursor.selfColored ? "Always in the accent" : Cursor.recolorable ? "Accent follows the shell's accent color" : ""
        Chips {
            visible: !Cursor.selfColored
            current: Cursor.recolorable ? Cursor.tint.charAt(0).toUpperCase() + Cursor.tint.slice(1) : Cursor.current?.color
            model: colorRow.colors.map(v => ({ value: v, label: v }))
            onPicked: v => {
                if (Cursor.recolorable)
                    Settings.cursorColor = v.toLowerCase();
                else
                    Cursor.pick(Cursor.current.family, Cursor.current.style, v);
            }
        }
    }

    SettingRow {
        label: "Cursor size"
        Chips {
            current: Settings.get("cursor_size")
            model: [20, 24, 28, 32, 40, 48].map(v => ({ value: v, label: String(v) }))
            onPicked: v => Settings.set("cursor_size", v)
        }
    }

    SectionTitle { text: "Cursor effects" }

    SettingRow {
        label: "Trail"
        hint: "Drawn behind the pointer as it moves"
        Chips {
            current: Settings.cursorTrail
            model: [{ value: "off", label: "Off" }, { value: "comet", label: "Comet" }, { value: "sparks", label: "Sparks" }]
            onPicked: v => Settings.cursorTrail = v
        }
    }

    SettingRow {
        label: "Music ring"
        hint: "Spectrum around the pointer while something plays"
        Toggle {
            checked: Settings.cursorViz
            onToggled: Settings.cursorViz = !checked
        }
    }

    // The ring's own options, unfolding under its switch
    Item {
        width: parent.width
        height: Settings.cursorViz ? vizOptions.implicitHeight : 0
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

        Column {
            id: vizOptions

            x: 16
            width: parent.width - 16
            opacity: Settings.cursorViz ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }

            SettingRow {
                label: "Look"
                Chips {
                    current: Settings.vizStyle
                    model: [{ value: "bars", label: "Bars" }, { value: "dots", label: "Dots" }, { value: "wave", label: "Wave" }, { value: "blob", label: "Blob" }]
                    onPicked: v => Settings.vizStyle = v
                }
            }
            SettingRow {
                label: "Bars"
                Chips {
                    current: Settings.vizBars
                    model: [24, 32, 48, 64, 96].map(v => ({ value: v, label: String(v) }))
                    onPicked: v => Settings.vizBars = v
                }
            }
            SettingRow {
                label: "Radius"
                hint: "Gap between the pointer and the ring"
                ValueSlider {
                    from: 12; to: 80; step: 1
                    value: Settings.vizRadius
                    format: v => v + " px"
                    onMoved: v => Settings.vizRadius = v
                }
            }
            SettingRow {
                label: "Height"
                hint: "How far the loudest bars reach"
                ValueSlider {
                    from: 8; to: 100; step: 1
                    value: Settings.vizHeight
                    format: v => v + " px"
                    onMoved: v => Settings.vizHeight = v
                }
            }
            SettingRow {
                label: "Spin"
                Toggle {
                    checked: Settings.vizSpin
                    onToggled: Settings.vizSpin = !checked
                }
            }
            SettingRow {
                label: "Keep up"
                hint: "Draws the ring where the pointer is heading, so it doesn't trail behind"
                Chips {
                    current: Settings.vizLead
                    model: [{ value: 0, label: "Off" }, { value: 14, label: "A little" }, { value: 36, label: "Full" }]
                    onPicked: v => Settings.vizLead = v
                }
            }
            SettingRow {
                label: "Hide when idle"
                hint: "Fades out once the mouse rests, like the pointer does"
                Chips {
                    current: Settings.cursorIdle
                    model: [{ value: 0, label: "Never" }, { value: 1, label: "1 s" }, { value: 2, label: "2 s" }, { value: 3, label: "3 s" }, { value: 5, label: "5 s" }]
                    onPicked: v => Settings.cursorIdle = v
                }
            }
        }
    }
}
