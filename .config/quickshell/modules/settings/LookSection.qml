import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

// Panel scale and Hyprland's window decoration
Column {
    id: root

    property bool shown: false
    // Scale the shell runs at now: a new one takes a restart
    readonly property real running: Number(Quickshell.env("QT_SCALE_FACTOR") || 1)

    spacing: 6

    SectionTitle { text: "Shell" }

    SettingRow {
        label: "Panel scale"
        hint: "Bar, popups and widgets, on top of the screen's own scale"

        Chips {
            current: Settings.panelScale
            model: [0.8, 0.9, 1, 1.1, 1.25, 1.5].map(v => ({ value: v, label: Math.round(v * 100) + "%" }))
            onPicked: v => Settings.panelScale = v
        }
    }

    Item {
        width: parent.width
        height: Math.abs(Settings.panelScale - root.running) > 0.001 ? restart.height + 6 : 0
        visible: height > 0

        PillButton {
            id: restart
            anchors.right: parent.right
            text: "Restart shell to apply"
            icon: "restart_alt"
            primary: true
            onClicked: Settings.restartShell()
        }
    }

    SettingRow {
        label: "Restart shell"
        hint: "Reloads Quickshell from scratch, e.g. after icon theme changes"

        PillButton {
            text: "Restart"
            icon: "restart_alt"
            onClicked: Settings.restartShell()
        }
    }

    SectionTitle { text: "Windows" }

    SettingRow {
        label: "Gaps between windows"
        ValueSlider {
            from: 0; to: 30; step: 1
            value: Settings.get("gaps_in")
            format: v => v + " px"
            onMoved: v => Settings.set("gaps_in", v)
        }
    }

    SettingRow {
        label: "Gaps around the screen"
        ValueSlider {
            from: 0; to: 60; step: 1
            value: Settings.get("gaps_out")
            format: v => v + " px"
            onMoved: v => Settings.set("gaps_out", v)
        }
    }

    SettingRow {
        label: "Border"
        ValueSlider {
            from: 0; to: 6; step: 1
            value: Settings.get("border_size")
            format: v => v + " px"
            onMoved: v => Settings.set("border_size", v)
        }
    }

    SettingRow {
        label: "Rounded corners"
        ValueSlider {
            from: 0; to: 30; step: 1
            value: Settings.get("rounding")
            format: v => v + " px"
            onMoved: v => Settings.set("rounding", v)
        }
    }

    SettingRow {
        label: "Unfocused windows"
        hint: "Opacity of windows without focus"
        ValueSlider {
            from: 0.5; to: 1; step: 0.05
            value: Settings.get("inactive_opacity")
            format: v => Math.round(v * 100) + "%"
            onMoved: v => Settings.set("inactive_opacity", v)
        }
    }

    SettingRow {
        label: "Blur"
        hint: "Behind see-through windows and panels"
        Toggle {
            checked: Settings.get("blur")
            onToggled: Settings.set("blur", !checked)
        }
    }

    SettingRow {
        label: "Shadows"
        Toggle {
            checked: Settings.get("shadows")
            onToggled: Settings.set("shadows", !checked)
        }
    }

    SectionTitle { text: "Animations" }

    SettingRow {
        label: "Animations"
        Toggle {
            checked: Settings.get("animations")
            onToggled: Settings.set("animations", !checked)
        }
    }

    SettingRow {
        label: "Speed"
        enabled: Settings.get("animations")
        opacity: enabled ? 1 : 0.45
        ValueSlider {
            from: 0.5; to: 2; step: 0.1
            value: Settings.get("anim_speed")
            format: v => v.toFixed(1) + "×"
            onMoved: v => Settings.set("anim_speed", v)
        }
    }

    SettingRow {
        label: "Windows open"
        enabled: Settings.get("animations")
        opacity: enabled ? 1 : 0.45
        Chips {
            current: Settings.get("window_style")
            model: [
                { value: "", label: "Pop in" },
                { value: "slide", label: "Slide" },
                { value: "gnomed", label: "Unfold" },
                { value: "popin 40%", label: "Zoom" }
            ]
            onPicked: v => Settings.set("window_style", v)
        }
    }

    SettingRow {
        label: "Workspaces switch"
        enabled: Settings.get("animations")
        opacity: enabled ? 1 : 0.45
        Chips {
            current: Settings.get("workspace_style")
            model: [
                { value: "", label: "Fade" },
                { value: "slide", label: "Slide" },
                { value: "slidevert", label: "Vertical" },
                { value: "slidefade 20%", label: "Slide + fade" }
            ]
            onPicked: v => Settings.set("workspace_style", v)
        }
    }
}
