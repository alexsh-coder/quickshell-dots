import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services

// Sliders on top, toggle tiles below. A tile's chevron (or a right click)
// swaps in that item's full page
Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var btDevice: Bluetooth.devices.values.find(d => d.connected) ?? null

    readonly property var profiles: [
        { value: PowerProfile.PowerSaver, icon: "energy_savings_leaf", label: "Eco" },
        { value: PowerProfile.Balanced, icon: "balance", label: "Balanced" },
        { value: PowerProfile.Performance, icon: "speed", label: "Boost" }
    ].filter(p => p.value !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
    readonly property int profileIndex: Math.max(0, profiles.findIndex(p => p.value === PowerProfiles.profile))

    readonly property int gap: 8
    readonly property int tileWidth: 168
    readonly property int tileHeight: 56
    readonly property int tileRadius: Theme.radius + 6

    property string greeting: ""
    property string uptime: ""

    implicitWidth: tileWidth * 2 + gap + Theme.pad * 2
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    function open(page) {
        root.popouts.detailRequested(page);
    }

    function volumeIcon(a) {
        return !a || a.muted || a.volume === 0 ? "volume_off"
            : a.volume < 0.34 ? "volume_mute"
            : a.volume < 0.67 ? "volume_down"
            : "volume_up";
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    Binding {
        target: root.popouts
        property: "busy"
        value: volumeRow.pressed || micRow.pressed || brightnessRow.pressed
        when: root.here
    }

    onHereChanged: if (here) {
        const h = new Date().getHours();
        greeting = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
        uptimeProc.running = true;
    }

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text));
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                root.uptime = "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
            }
        }
    }

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 16

        Item {
            width: parent.width
            height: 36

            Column {
                anchors.left: parent.left
                anchors.right: headerButtons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.greeting + (Quickshell.env("USER") ? ", " + Quickshell.env("USER") : "")
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Label {
                    text: root.uptime
                    font.pixelSize: 12
                    color: Theme.subtext
                }
            }

            Row {
                id: headerButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Desktop widgets and effects editor
                RoundButton {
                    icon: "dashboard_customize"
                    onClicked: {
                        root.popouts.close();
                        Desk.editing = true;
                    }
                }
                RoundButton {
                    icon: "settings"
                    onClicked: {
                        root.popouts.close();
                        Settings.open = true;
                    }
                }
                RoundButton {
                    icon: "lock"
                    onClicked: {
                        root.popouts.close();
                        Quickshell.execDetached(["loginctl", "lock-session"]);
                    }
                }
                RoundButton {
                    icon: "power_settings_new"
                    onClicked: root.open("power")
                }
            }
        }

        Column {
            width: parent.width
            spacing: 10

            SliderRow {
                id: volumeRow
                visible: !!root.sink?.audio
                icon: root.volumeIcon(root.sink?.audio)
                value: root.sink?.audio?.volume ?? 0
                dim: root.sink?.audio?.muted ?? false
                onIconClicked: root.sink.audio.muted = !root.sink.audio.muted
                onMoved: v => {
                    root.sink.audio.volume = v;
                    if (root.sink.audio.muted && v > 0)
                        root.sink.audio.muted = false;
                }
            }

            SliderRow {
                id: micRow
                visible: !!root.source?.audio
                icon: root.source?.audio?.muted ? "mic_off" : "mic"
                value: root.source?.audio?.volume ?? 0
                dim: root.source?.audio?.muted ?? false
                onIconClicked: root.source.audio.muted = !root.source.audio.muted
                onMoved: v => {
                    root.source.audio.volume = v;
                    if (root.source.audio.muted && v > 0)
                        root.source.audio.muted = false;
                }
            }

            SliderRow {
                id: brightnessRow
                visible: Brightness.available
                icon: Brightness.value < 0.34 ? "brightness_low" : Brightness.value < 0.67 ? "brightness_medium" : "brightness_high"
                value: Brightness.value
                clickable: false
                onMoved: v => Brightness.set(v)
            }
        }

        Grid {
            columns: 2
            rowSpacing: root.gap
            columnSpacing: root.gap

            Tile {
                visible: !!Net.wifi
                icon: Net.wifiOn ? "wifi" : "wifi_off"
                title: "Wi-Fi"
                detail: Net.active?.name ?? (Net.ethernet ? "Ethernet" : Net.wifiOn ? "Not connected" : "Off")
                on: Net.wifiOn
                page: "network"
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }

            Tile {
                visible: !!root.adapter
                icon: !on ? "bluetooth_disabled" : root.btDevice ? "bluetooth_connected" : "bluetooth"
                title: "Bluetooth"
                detail: !on ? "Off" : root.btDevice?.name ?? "On"
                on: root.adapter?.enabled ?? false
                page: "bluetooth"
                onClicked: root.adapter.enabled = !on
            }

            Tile {
                visible: Vpn.available
                icon: Vpn.on ? "vpn_key" : "vpn_key_off"
                title: "VPN"
                detail: Vpn.busy ? (Vpn.on ? "Disconnecting…" : "Connecting…")
                    : Vpn.on ? (Vpn.split(Vpn.current).name || "Connected")
                    : "Off"
                on: Vpn.on
                busy: Vpn.busy
                page: "vpn"
                onClicked: Vpn.toggle()
            }

            Tile {
                icon: on ? "do_not_disturb_on" : "notifications"
                title: "Do not disturb"
                detail: on ? "Silenced" : "Off"
                on: Notifs.dnd
                onClicked: Notifs.setDnd(!on)
            }

            Tile {
                icon: "nightlight"
                title: "Night light"
                detail: on ? "Warm" : "Off"
                on: NightMode.enabled
                onClicked: NightMode.toggle()
            }

            Tile {
                icon: "coffee"
                title: "Caffeine"
                detail: on ? "Staying awake" : "Off"
                on: Caffeine.enabled
                onClicked: Caffeine.toggle()
            }

            Tile {
                icon: on ? "dark_mode" : "light_mode"
                title: "Dark mode"
                detail: on ? "On" : "Off"
                on: !Scheme.light
                onClicked: Scheme.toggle()
            }

            Tile {
                icon: root.profiles[root.profileIndex].icon
                title: "Power mode"
                detail: root.profiles[root.profileIndex].label
                on: PowerProfiles.profile !== PowerProfile.Balanced
                onClicked: PowerProfiles.profile = root.profiles[(root.profileIndex + 1) % root.profiles.length].value
            }

            Tile {
                icon: "equalizer"
                title: "Visualizer"
                detail: on && Desk.main ? Desk.main.style.charAt(0).toUpperCase() + Desk.main.style.slice(1) : "Off"
                on: MusicFx.desktop
                page: "media"
                onClicked: MusicFx.set("desktop", !MusicFx.desktop)
            }

            Tile {
                icon: "lyrics"
                title: "Lyrics"
                detail: !on ? "Off" : Lyrics.lines.length > 0 ? "Showing" : "Waiting for music"
                on: MusicFx.lyrics
                onClicked: MusicFx.lyrics = !MusicFx.lyrics
            }
        }
    }

    component RoundButton: Rectangle {
        id: button

        property string icon
        signal clicked

        width: 34
        height: 34
        radius: height / 2
        color: area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Icon {
            anchors.centerIn: parent
            text: button.icon
            font.pixelSize: 18
            fill: 0
            color: area.containsMouse ? Theme.accent : Theme.text
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component SliderRow: Item {
        id: row

        property string icon
        property real value
        property bool dim: false
        property bool clickable: true
        readonly property bool pressed: slider.pressed
        signal moved(real v)
        signal iconClicked

        width: parent.width
        height: 32

        Rectangle {
            id: iconButton

            width: 32
            height: 32
            radius: height / 2
            color: row.dim ? Theme.surface : Qt.tint(Theme.bg, Qt.alpha(Theme.accent, iconMouse.containsMouse && row.clickable ? 0.22 : 0.14))
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            Icon {
                anchors.centerIn: parent
                text: row.icon
                font.pixelSize: 18
                color: row.dim ? Theme.subtext : Theme.accent
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }

            MouseArea {
                id: iconMouse
                anchors.fill: parent
                enabled: row.clickable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.iconClicked()
            }
        }

        Slider {
            id: slider
            anchors.left: iconButton.right
            anchors.leftMargin: 14
            anchors.right: pct.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            value: row.value
            dim: row.dim
            onMoved: v => row.moved(v)
        }

        Label {
            id: pct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: Math.round(row.value * 100) + "%"
            font.pixelSize: 12
            color: Theme.subtext
        }
    }

    // Off, the icon sits in a small bubble; on, the bubble floods the whole tile
    component Tile: Item {
        id: tile

        property string icon
        property string title
        property string detail
        property bool on: false
        property bool busy: false
        // Popout page behind the chevron
        property string page: ""
        signal clicked

        readonly property bool hovered: area.containsMouse || moreMouse.containsMouse
        readonly property int inset: 8
        readonly property int bubble: root.tileHeight - inset * 2

        width: root.tileWidth
        height: root.tileHeight
        scale: area.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }

        Rectangle {
            anchors.fill: parent
            radius: root.tileRadius
            color: Theme.surface
        }

        Rectangle {
            id: flood

            // 0 = bubble behind the icon, 1 = the whole tile
            property real grow: tile.on ? 1 : 0

            x: tile.inset * (1 - grow)
            y: tile.inset * (1 - grow)
            width: tile.bubble + (tile.width - tile.bubble) * grow
            height: tile.bubble + (tile.height - tile.bubble) * grow
            radius: tile.bubble / 2 + (root.tileRadius - tile.bubble / 2) * grow
            // Opaque tint: fading towards a translucent color overshoots and flashes
            color: tile.on ? Theme.accent : Qt.tint(Theme.surface, Qt.alpha(Theme.text, 0.08))
            Behavior on color { ColorAnimation { duration: Theme.anim } }
            Behavior on grow {
                NumberAnimation {
                    duration: tile.on ? Theme.animPanel : 300
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: tile.on ? Theme.emphasizedDecel : Theme.emphasizedAccel
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.tileRadius
            color: Qt.alpha(tile.on ? Theme.bg : Theme.text, tile.hovered ? 0.08 : 0)
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        Icon {
            id: glyph

            x: tile.inset + (tile.bubble - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: tile.icon
            font.pixelSize: 20
            fill: tile.on ? 1 : 0
            color: tile.on ? Theme.bg : Theme.text
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            SequentialAnimation on opacity {
                running: tile.busy
                loops: Animation.Infinite
                onRunningChanged: if (!running) glyph.opacity = 1
                NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: tile.inset + tile.bubble + 10
            anchors.right: more.visible ? more.left : parent.right
            anchors.rightMargin: more.visible ? 0 : 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Label {
                width: parent.width
                text: tile.title
                elide: Text.ElideRight
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: tile.on ? Theme.bg : Theme.text
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }
            Label {
                width: parent.width
                text: tile.detail
                elide: Text.ElideRight
                font.pixelSize: 11
                color: tile.on ? Qt.alpha(Theme.bg, 0.72) : Theme.subtext
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    if (tile.page)
                        root.open(tile.page);
                } else {
                    tile.clicked();
                }
            }
        }

        Item {
            id: more

            visible: tile.page !== ""
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(tile.on ? Theme.bg : Theme.text, moreMouse.containsMouse ? 0.12 : 0)
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }

            Icon {
                anchors.centerIn: parent
                text: "chevron_right"
                font.pixelSize: 20
                fill: 0
                color: tile.on ? Theme.bg : Theme.subtext
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }

            MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open(tile.page)
            }
        }
    }
}
