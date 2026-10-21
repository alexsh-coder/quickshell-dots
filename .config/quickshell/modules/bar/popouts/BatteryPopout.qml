import QtQuick
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property real frac: dev?.percentage ?? 0
    readonly property int state: dev?.state ?? UPowerDeviceState.Unknown
    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool full: state === UPowerDeviceState.FullyCharged || (!UPower.onBattery && frac >= 0.99)
    readonly property bool low: !charging && frac <= 0.15

    readonly property var profiles: [
        { value: PowerProfile.PowerSaver, icon: "energy_savings_leaf", label: "Eco" },
        { value: PowerProfile.Balanced, icon: "balance", label: "Balanced" },
        { value: PowerProfile.Performance, icon: "speed", label: "Boost" }
    ].filter(p => p.value !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

    function duration(s) {
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
        return h ? `${h} h ${m} min` : `${m} min`;
    }

    readonly property string status: full ? "Fully charged"
        : charging ? (dev.timeToFull > 0 ? `Full in ${duration(dev.timeToFull)}` : "Charging")
        : !UPower.onBattery ? "Plugged in, not charging"
        : dev?.timeToEmpty > 0 ? `${duration(dev.timeToEmpty)} left`
        : "On battery"

    Binding {
        target: SystemStats
        property: "active"
        value: root.here
    }

    implicitWidth: 336
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 14

        Item {
            width: parent.width
            height: 40

            Label {
                id: pct
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(root.frac * 100) + "%"
                font.pixelSize: 28
                font.weight: Font.Bold
                color: root.low ? Theme.urgent : Theme.text
            }

            Column {
                anchors.left: pct.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    text: root.status
                    font.pixelSize: 13
                }
                Label {
                    text: [
                        Math.abs(root.dev?.changeRate ?? 0) > 0.1 ? Math.abs(root.dev.changeRate).toFixed(1) + " W" : "",
                        root.dev?.healthSupported ? "health " + Math.round(root.dev.healthPercentage) + "%" : ""
                    ].filter(s => s).join(" · ")
                    font.pixelSize: 11
                    color: Theme.subtext
                }
            }
        }

        // Charge level; a soft glint runs along it while charging
        Rectangle {
            width: parent.width
            height: 10
            radius: 5
            color: Theme.muted
            clip: true

            Rectangle {
                id: level
                width: Math.max(parent.height, parent.width * root.frac)
                clip: true
                height: parent.height
                radius: parent.radius
                color: root.low ? Theme.urgent : Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }

                Rectangle {
                    id: glint
                    visible: root.charging && root.here
                    width: 40
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.alpha("white", 0.45) }
                        GradientStop { position: 1; color: "transparent" }
                    }

                    NumberAnimation on x {
                        running: glint.visible
                        loops: Animation.Infinite
                        from: -glint.width
                        to: level.width
                        duration: 1600
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        // System load
        Row {
            width: parent.width
            spacing: 16

            Stat { label: "CPU"; value: SystemStats.cpu }
            Stat { label: "RAM"; value: SystemStats.ram; detail: SystemStats.ramUsedGb.toFixed(1) + "G" }
            Stat { label: "GPU"; value: SystemStats.gpu; visible: SystemStats.gpu >= 0 }
        }

        // Power profile switch with a sliding indicator
        Rectangle {
            id: profiles

            readonly property int count: root.profiles.length
            readonly property int current: Math.max(0, root.profiles.findIndex(p => p.value === PowerProfiles.profile))
            readonly property real slot: (width - 8) / count

            width: parent.width
            height: 40
            radius: Theme.radius
            color: Theme.surface

            Rectangle {
                x: 4 + profiles.slot * profiles.current
                y: 4
                width: profiles.slot
                height: parent.height - 8
                radius: Theme.radius - 4
                color: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.2))
                Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
            }

            Row {
                x: 4
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: root.profiles

                    Item {
                        id: opt

                        required property var modelData
                        required property int index
                        readonly property bool on: index === profiles.current

                        width: profiles.slot
                        height: 32

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: opt.modelData.icon
                                font.pixelSize: 17
                                fill: 0
                                color: opt.on ? Theme.accent : Theme.subtext
                                Behavior on color { ColorAnimation { duration: Theme.anim } }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: opt.modelData.label
                                font.pixelSize: 12
                                color: opt.on ? Theme.text : Theme.subtext
                                Behavior on color { ColorAnimation { duration: Theme.anim } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PowerProfiles.profile = opt.modelData.value
                        }
                    }
                }
            }
        }

        // Night light and caffeine
        Rectangle {
            width: parent.width
            height: switches.implicitHeight + 8
            radius: Theme.radius
            color: Theme.surface

            Column {
                id: switches
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter

                Switch {
                    icon: "bedtime"
                    label: "Night mode"
                    checked: NightMode.enabled
                    onToggled: NightMode.toggle()
                }
                Switch {
                    icon: "coffee"
                    label: "Caffeine"
                    checked: Caffeine.enabled
                    onToggled: Caffeine.toggle()
                }
            }
        }
    }

    component Switch: Item {
        id: sw

        property string icon
        property string label
        property bool checked
        signal toggled

        width: parent.width
        height: 40

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: sw.icon
                font.pixelSize: 18
                fill: 0
                color: sw.checked ? Theme.accent : Theme.subtext
                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: sw.label
                font.pixelSize: 13
            }
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            checked: sw.checked
            onToggled: sw.toggled()
        }
    }

    component Stat: Column {
        id: stat

        property string label
        property real value
        property string detail: ""
        readonly property int shown: (SystemStats.gpu >= 0) ? 3 : 2

        width: (content.width - 16 * (shown - 1)) / shown
        spacing: 6

        Item {
            width: parent.width
            height: 16

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: stat.label
                font.pixelSize: 11
                font.weight: Font.Bold
                color: Theme.subtext
            }

            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: stat.detail || Math.round(stat.value * 100) + "%"
                font.pixelSize: 12
                color: stat.value > 0.85 ? Theme.urgent : Theme.text
            }
        }

        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: Theme.muted

            Rectangle {
                width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, stat.value)))
                height: parent.height
                radius: parent.radius
                color: stat.value > 0.85 ? Theme.urgent : Theme.text
                opacity: 0.85
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
            }
        }
    }
}
