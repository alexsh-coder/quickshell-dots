import QtQuick
import qs.config
import qs.components
import qs.services

// Music effects: intensity, desktop visualizer style, lyrics and wallpaper effect toggles
Column {
    id: root

    // Effect whose own strength slider is shown, opened by right-clicking it
    property string editing: ""
    readonly property var names: ({ desktop: "Visualizer", glow: "Glow", blur: "Blur", zoom: "Zoom", shake: "Shake", glitch: "Glitch", pulse: "Pulse", ripple: "Ripple", bloom: "Bloom", vhs: "VHS", hue: "Hue", rgb: "RGB split" })
    readonly property var styleIcons: ({ bars: "graphic_eq", wave: "airwave", mirror: "align_vertical_center", ring: "donut_large", nation: "album", particles: "auto_awesome", line: "horizontal_rule", blob: "bubble_chart", dots: "blur_linear" })
    // A slider is held
    readonly property bool busy: intensitySlider.pressed || strengthSlider.pressed
    // Tiles stay see-through over the blurred cover behind the panel
    readonly property color tile: Qt.alpha(Theme.surface, 0.7)

    // Stays on the last effect while the slider folds away
    property string shownKey: "glow"

    function edit(key) {
        editing = editing === key ? "" : key;
        if (editing)
            shownKey = editing;
    }

    signal customize

    function styleName(s) {
        return s ? s[0].toUpperCase() + s.slice(1) : "";
    }

    spacing: 16

    // Intensity
    Column {
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 22

            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Icon { text: "music_note"; font.pixelSize: 20; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Intensity"; anchors.verticalCenter: parent.verticalCenter }
            }

            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(MusicFx.intensity * 100) + "%"
                color: Theme.subtext
            }
        }

        FxSlider {
            id: intensitySlider
            width: parent.width
            min: 0.25
            value: MusicFx.intensity
            onMoved: v => MusicFx.setIntensity(v)
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.muted }

    // Desktop visualizer
    Column {
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 24

            Label { text: "Desktop visualizer"; anchors.verticalCenter: parent.verticalCenter }

            GainBadge { key: "desktop"; anchors.right: parent.right; anchors.rightMargin: 50; anchors.verticalCenter: parent.verticalCenter }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: root.edit("desktop")
            }

            Switch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: MusicFx.desktop
                onToggled: MusicFx.set("desktop", !MusicFx.desktop)
            }
        }

        Grid {
            columns: 3
            width: parent.width
            spacing: 6

            Repeater {
                model: MusicFx.styles

                Rectangle {
                    id: chip

                    required property string modelData
                    readonly property bool selected: MusicFx.desktop && Desk.main?.style === modelData
                    readonly property bool layered: MusicFx.desktop && !selected && MusicFx.hasLayer(modelData)

                    width: (parent.width - 12) / 3
                    height: 52
                    radius: Theme.radius
                    color: selected ? Theme.accent : layered ? Qt.alpha(Theme.accent, 0.16) : chipMouse.containsMouse ? Theme.muted : root.tile
                    border.width: 1
                    border.color: layered ? Qt.alpha(Theme.accent, 0.6) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.styleIcons[chip.modelData]
                            font.pixelSize: 20
                            fill: chip.selected || chip.layered ? 1 : 0
                            color: chip.selected ? Theme.bg : chip.layered ? Theme.accent : Theme.text
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: chip.modelData[0].toUpperCase() + chip.modelData.slice(1)
                            font.pixelSize: 12
                            color: chip.selected ? Theme.bg : Theme.subtext
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        // Left picks the main style, right adds or removes it as a layer behind it.
                        // Either turns the visualizer on.
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (!chip.selected)
                                    MusicFx.toggleLayer(chip.modelData);
                            } else {
                                MusicFx.setStyle(chip.modelData);
                            }
                            MusicFx.set("desktop", true);
                        }
                    }
                }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.muted }

    Item {
        width: parent.width
        height: 24

        Label { text: "Desktop lyrics"; anchors.verticalCenter: parent.verticalCenter }

        Switch {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: MusicFx.lyrics
            onToggled: MusicFx.lyrics = !MusicFx.lyrics
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.muted }

    Column {
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 24

            Label { text: "Wallpaper effects"; anchors.verticalCenter: parent.verticalCenter }

            Switch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: MusicFx.wallpaperFx
                onToggled: MusicFx.setWallpaperFx(!MusicFx.wallpaperFx)
            }
        }

        Column {
            width: parent.width

            // Effects
            Grid {
                width: parent.width
                columns: 2
                spacing: 6

                Tile { icon: "flare"; label: "Glow"; key: "glow" }
                Tile { icon: "blur_on"; label: "Blur"; key: "blur" }
                Tile { icon: "zoom_out_map"; label: "Zoom"; key: "zoom" }
                Tile { icon: "earthquake"; label: "Shake"; key: "shake" }
                Tile { icon: "broken_image"; label: "Glitch"; key: "glitch" }
                Tile { icon: "bolt"; label: "Pulse"; key: "pulse" }
                Tile { icon: "waves"; label: "Ripple"; key: "ripple" }
                Tile { icon: "light_mode"; label: "Bloom"; key: "bloom" }
                Tile { icon: "live_tv"; label: "VHS"; key: "vhs" }
                Tile { icon: "palette"; label: "Hue"; key: "hue" }
                Tile { icon: "gradient"; label: "RGB"; key: "rgb" }
            }

            // Strength of one effect, slides open under the grid
            Item {
                id: editor

                readonly property string key: root.shownKey

                width: parent.width
                height: root.editing ? editorCol.implicitHeight + 14 : 0
                clip: true
                opacity: root.editing ? 1 : 0
                Behavior on height { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                Column {
                    id: editorCol

                    y: 14
                    width: parent.width
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 20

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.names[editor.key] ?? "") + " strength"
                            font.pixelSize: 14
                        }
                        Label {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(MusicFx.gain(editor.key) * 100) + "%"
                            font.pixelSize: 14
                            color: Theme.subtext
                        }
                    }

                    FxSlider {
                        id: strengthSlider
                        width: parent.width
                        min: 0.1
                        value: MusicFx.gain(editor.key)
                        onMoved: v => MusicFx.setGain(editor.key, v)
                    }

                    // Glitch only: how the wallpaper tears
                    Column {
                        id: styleBox

                        property bool open: false

                        width: parent.width
                        spacing: 4
                        visible: editor.key === "glitch"

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: Theme.radius
                            color: styleHead.containsMouse ? Theme.muted : root.tile
                            Behavior on color { ColorAnimation { duration: Theme.anim } }

                            Label { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Style"; font.pixelSize: 14 }
                            Label {
                                anchors.right: chev.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.styleName(MusicFx.glitchStyle)
                                font.pixelSize: 14
                                color: Theme.subtext
                            }
                            Icon {
                                id: chev
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: styleBox.open ? "expand_less" : "expand_more"
                                font.pixelSize: 20
                                color: Theme.subtext
                            }
                            MouseArea {
                                id: styleHead
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: styleBox.open = !styleBox.open
                            }
                        }

                        Repeater {
                            model: styleBox.open ? MusicFx.glitchStyles : []

                            Rectangle {
                                id: opt

                                required property string modelData
                                readonly property bool current: MusicFx.glitchStyle === modelData

                                width: styleBox.width
                                height: 32
                                radius: Theme.radius
                                color: current ? Qt.alpha(Theme.accent, 0.16) : optMouse.containsMouse ? Theme.muted : "transparent"

                                Label {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.styleName(opt.modelData)
                                    font.pixelSize: 14
                                    color: opt.current ? Theme.accent : Theme.text
                                }
                                MouseArea {
                                    id: optMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        MusicFx.set("glitchStyle", opt.modelData);
                                        styleBox.open = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.muted }

    // Everything else (where widgets sit, more visualizers, glow type) lives in the desktop editor
    Rectangle {
        width: parent.width
        height: 44
        radius: Theme.radius
        color: customizeArea.containsMouse ? Theme.muted : root.tile
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10

            Icon { text: "dashboard_customize"; font.pixelSize: 20; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            Label { text: "Customize desktop"; anchors.verticalCenter: parent.verticalCenter }
        }

        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "chevron_right"
            font.pixelSize: 20
            color: Theme.subtext
        }

        MouseArea {
            id: customizeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.customize()
        }
    }

    component Switch: Rectangle {
        id: sw

        property bool checked
        signal toggled

        width: 40
        height: 22
        radius: height / 2
        color: checked ? Theme.accent : Theme.muted
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Rectangle {
            x: sw.checked ? sw.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: sw.checked ? Theme.bg : Theme.text
            Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    component Tile: Rectangle {
        id: tile

        property string icon
        property string label
        property string key
        readonly property bool on: MusicFx[key]

        width: (root.width - 6) / 2
        height: 44
        radius: Theme.radius
        color: on ? Qt.alpha(Theme.accent, 0.16) : tileMouse.containsMouse ? Theme.muted : root.tile
        border.width: 1
        border.color: root.editing === key ? Theme.text : on ? Qt.alpha(Theme.accent, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        GainBadge {
            key: tile.key
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.icon
                font.pixelSize: 20
                fill: tile.on ? 1 : 0
                color: tile.on ? Theme.accent : Theme.subtext
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.label
                font.pixelSize: 14
                color: tile.on ? Theme.text : Theme.subtext
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    root.edit(tile.key);
                else
                    MusicFx.set(tile.key, !tile.on);
            }
        }
    }

    // Shows a non-default strength, e.g. "150%"
    component GainBadge: Label {
        property string key
        readonly property real gain: MusicFx.gain(key)

        visible: gain !== 1
        text: Math.round(gain * 100) + "%"
        font.pixelSize: 11
        color: Theme.subtext
    }

    component FxSlider: Item {
        id: slider

        property real value
        property real min: 0.1
        property real max: 2
        readonly property real frac: (value - min) / (max - min)
        readonly property bool pressed: drag.pressed
        signal moved(real v)

        height: 20

        function setFrom(x) {
            moved(min + Math.max(0, Math.min(1, x / width)) * (max - min));
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Theme.muted

            // Fill breathes with the music, so the slider shows what it scales
            Rectangle {
                width: Math.max(height, parent.width * slider.frac)
                height: parent.height
                radius: parent.radius
                color: Theme.accent
                opacity: 0.75 + Cava.level * 0.25
            }
        }

        // 100% mark
        Rectangle {
            x: parent.width * (1 - slider.min) / (slider.max - slider.min) - 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 12
            radius: 1
            color: Theme.subtext
            opacity: 0.6
        }

        Rectangle {
            x: parent.width * slider.frac - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: drag.pressed ? 18 : 16
            height: width
            radius: width / 2
            color: Theme.text
            Behavior on width { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -6
            // Inside the popout's scrolling list: a drag here moves the slider, not the list
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => slider.setFrom(mouse.x - 6)
            onPositionChanged: mouse => { if (pressed) slider.setFrom(mouse.x - 6); }
            onDoubleClicked: slider.moved(1)
        }
    }
}
