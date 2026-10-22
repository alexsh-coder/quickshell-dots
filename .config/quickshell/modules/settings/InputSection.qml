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

    SettingRow {
        label: "Cursor size"
        hint: "Some apps pick it up after a restart"
        Chips {
            current: Settings.get("cursor_size")
            model: [20, 24, 28, 32, 40, 48].map(v => ({ value: v, label: String(v) }))
            onPicked: v => Settings.set("cursor_size", v)
        }
    }
}
