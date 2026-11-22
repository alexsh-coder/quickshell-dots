import QtQuick
import QtQuick.Controls as QQC
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
    // Sections are built on first view and dropped a minute after the card closes
    readonly property bool alive: win.visible || warm.running
    property var seen: []
    // Where each section was scrolled to, so the card reopens where it was left
    property var scrolls: ({})
    onSectionChanged: if (!seen.includes(section)) seen = seen.concat(section)
    onAliveChanged: if (!alive) seen = []

    Timer {
        id: warm
        interval: 60000
    }

    readonly property var sections: [
        { name: "wallpaper", label: "Wallpaper", icon: "wallpaper" },
        { name: "display", label: "Display", icon: "monitor" },
        { name: "look", label: "Appearance", icon: "palette" },
        { name: "input", label: "Input", icon: "keyboard" },
        { name: "power", label: "Power", icon: "battery_horiz_075" },
        { name: "keybinds", label: "Keybinds", icon: "keyboard_command_key" },
        { name: "remote", label: "Remote", icon: "lan" }
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
        onVisibleChanged: if (!visible) warm.restart()

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
                // The card's clip is square, so the rail rounds its own outer corners
                topLeftRadius: card.radius
                bottomLeftRadius: card.radius
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

                HoverHandler {
                    id: flickHover
                }

                // Thin draggable bar, shown only while the pointer is near the right edge
                QQC.ScrollBar.vertical: QQC.ScrollBar {
                    id: vbar

                    readonly property bool near: flickHover.hovered && flickHover.point.position.x > flick.width - 56

                    parent: flick.parent
                    x: flick.x + flick.width - width - 4
                    y: flick.y + Theme.pad
                    height: flick.height - Theme.pad * 2
                    width: 8
                    padding: 0
                    policy: flick.contentHeight > flick.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
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

                Item {
                    id: pages

                    x: Theme.pad + 8
                    y: Theme.pad - 6
                    width: flick.width - (Theme.pad + 8) * 2
                    height: current?.item?.implicitHeight ?? 0

                    readonly property Item current: ({ wallpaper: wallpaperPage, display: displayPage, look: lookPage, input: inputPage, power: powerPage, keybinds: keybindsPage, remote: remotePage })[root.section] ?? null

                    Page { id: wallpaperPage; name: "wallpaper"; sourceComponent: WallpaperSection { width: wallpaperPage.width; shown: Settings.open && wallpaperPage.visible } }
                    Page { id: displayPage; name: "display"; sourceComponent: DisplaySection { width: displayPage.width; shown: Settings.open && displayPage.visible } }
                    Page { id: lookPage; name: "look"; sourceComponent: LookSection { width: lookPage.width; shown: Settings.open && lookPage.visible } }
                    Page { id: inputPage; name: "input"; sourceComponent: InputSection { width: inputPage.width; shown: Settings.open && inputPage.visible } }
                    Page { id: powerPage; name: "power"; sourceComponent: PowerSection { width: powerPage.width; shown: Settings.open && powerPage.visible } }
                    Page { id: keybindsPage; name: "keybinds"; sourceComponent: KeybindsSection { width: keybindsPage.width; shown: Settings.open && keybindsPage.visible } }
                    Page { id: remotePage; name: "remote"; sourceComponent: RemoteSection { width: remotePage.width; shown: Settings.open && remotePage.visible } }
                }

                // Each section reopens where it was left. The page may still be loading, so the
                // position is held until it's tall enough
                property string shownSection: root.section
                property real wanted: -1

                function restore() {
                    wanted = root.scrolls[root.section] ?? 0;
                    hold();
                }
                function hold() {
                    if (wanted < 0)
                        return;
                    const top = Math.max(0, contentHeight - height);
                    contentY = Math.min(wanted, top);
                    if (top >= wanted)
                        wanted = -1;
                }

                onContentHeightChanged: hold()
                onContentYChanged: if (wanted < 0 && Settings.open) root.scrolls[shownSection] = contentY
                onMovementStarted: wanted = -1

                Connections {
                    target: root
                    function onSectionChanged() {
                        flick.shownSection = root.section;
                        flick.restore();
                    }
                }
                Connections {
                    target: Settings
                    function onOpenChanged() {
                        if (Settings.open)
                            flick.restore();
                    }
                }
            }
        }
    }

    component Page: Loader {
        required property string name

        width: parent.width
        visible: root.section === name
        active: root.alive && (visible || root.seen.includes(name))
    }

    function step(by) {
        const i = sections.findIndex(s => s.name === section);
        section = sections[(i + by + sections.length) % sections.length].name;
    }
}
