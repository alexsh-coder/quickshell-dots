import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// Settings card in the middle of the focused screen: sections on the left, the open one on the right
Scope {
    id: root

    property ShellScreen screen: Quickshell.screens[0]
    property string section: "wallpaper"

    readonly property var sections: [
        { name: "wallpaper", label: "Wallpaper", icon: "wallpaper" },
        { name: "display", label: "Display", icon: "monitor" },
        { name: "look", label: "Appearance", icon: "palette" },
        { name: "input", label: "Input", icon: "keyboard" },
        { name: "power", label: "Power", icon: "battery_horiz_075" }
    ]

    Connections {
        target: Settings
        function onOpenChanged() {
            if (!Settings.open)
                return;
            root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
            keys.forceActiveFocus();
        }
    }

    PanelWindow {
        id: win

        screen: root.screen
        visible: Settings.open || card.opacity > 0

        WlrLayershell.namespace: "settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Settings.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: Settings.open ? 0.3 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Settings.open = false
        }

        Rectangle {
            id: card

            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: Math.min(parent.width - 80, 940)
            height: Math.min(parent.height - 80, 680)
            radius: Theme.radius + 6
            color: Qt.alpha(Theme.bg, 0.92)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.25)
            clip: true

            opacity: Settings.open ? 1 : 0
            scale: Settings.open ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Settings.open ? Easing.OutBack : Easing.InCubic } }

            // Swallows clicks so they don't reach the close-on-outside-click area
            MouseArea {
                anchors.fill: parent
            }

            Item {
                id: keys
                focus: true
                Keys.onEscapePressed: Settings.open = false
                Keys.onUpPressed: root.step(-1)
                Keys.onDownPressed: root.step(1)
            }

            Rectangle {
                id: rail

                width: 210
                height: parent.height
                color: Qt.alpha(Theme.surface, 0.7)

                Column {
                    x: 12
                    y: Theme.padTop + 4
                    width: parent.width - 24
                    spacing: 4

                    Row {
                        x: 8
                        bottomPadding: 14
                        spacing: 10

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "settings"
                            font.pixelSize: 22
                            color: Theme.accent
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Settings"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: root.sections

                        Rectangle {
                            id: entry

                            required property var modelData
                            readonly property bool on: root.section === modelData.name

                            width: parent.width
                            height: 40
                            radius: height / 2
                            color: on ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.22))
                                : area.containsMouse ? Qt.alpha(Theme.text, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.anim } }

                            Row {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.icon
                                    font.pixelSize: 20
                                    fill: entry.on ? 1 : 0
                                    color: entry.on ? Theme.accent : Theme.text
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.label
                                    font.pixelSize: 14
                                    font.weight: entry.on ? Font.DemiBold : Font.Medium
                                    color: entry.on ? Theme.accent : Theme.text
                                }
                            }

                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.section = entry.modelData.name
                            }
                        }
                    }
                }
            }

            Flickable {
                id: flick

                anchors.left: rail.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                contentWidth: width
                contentHeight: pages.height + Theme.pad * 2
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Item {
                    id: pages

                    x: Theme.pad + 8
                    y: Theme.pad - 6
                    width: flick.width - (Theme.pad + 8) * 2
                    height: current?.implicitHeight ?? 0

                    readonly property Item current: ({ wallpaper: wallpaperPage, display: displayPage, look: lookPage, input: inputPage, power: powerPage })[root.section] ?? null

                    WallpaperSection { id: wallpaperPage; width: parent.width; visible: root.section === "wallpaper"; shown: Settings.open && visible }
                    DisplaySection { id: displayPage; width: parent.width; visible: root.section === "display"; shown: Settings.open && visible }
                    LookSection { id: lookPage; width: parent.width; visible: root.section === "look"; shown: Settings.open && visible }
                    InputSection { id: inputPage; width: parent.width; visible: root.section === "input"; shown: Settings.open && visible }
                    PowerSection { id: powerPage; width: parent.width; visible: root.section === "power"; shown: Settings.open && visible }
                }

                // Each section opens at its top
                Connections {
                    target: root
                    function onSectionChanged() {
                        flick.contentY = 0;
                    }
                }
            }
        }
    }

    function step(by) {
        const i = sections.findIndex(s => s.name === section);
        section = sections[(i + by + sections.length) % sections.length].name;
    }
}
