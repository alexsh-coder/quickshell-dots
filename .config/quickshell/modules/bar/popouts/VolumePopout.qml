import QtQuick
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)

    implicitWidth: 320
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    PwObjectTracker {
        objects: [root.sink]
    }

    Binding {
        target: root.popouts
        property: "busy"
        value: output.pressed
        when: root.here
    }

    Binding {
        target: OsdGate
        property: "volumePanel"
        value: true
        when: root.here
    }

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 14

        Channel {
            id: output
            node: root.sink
            icons: ["volume_off", "volume_mute", "volume_down", "volume_up"]
            title: "Output"
        }

        Rectangle {
            visible: root.sinks.length > 1
            width: parent.width
            height: 1
            color: Theme.muted
        }

        Column {
            visible: root.sinks.length > 1
            width: parent.width
            spacing: 2

            Repeater {
                model: root.sinks

                Rectangle {
                    id: device

                    required property PwNode modelData
                    readonly property bool current: modelData === root.sink

                    width: parent.width
                    height: 36
                    radius: Theme.radius - 2
                    color: hover.containsMouse ? Theme.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Icon {
                        id: devIcon
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: /headphone|headset/i.test(device.modelData.description + device.modelData.name) ? "headphones" : "speaker"
                        font.pixelSize: 19
                        fill: device.current ? 1 : 0
                        color: device.current ? Theme.accent : Theme.subtext
                    }

                    Label {
                        anchors.left: devIcon.right
                        anchors.leftMargin: 10
                        anchors.right: check.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: device.modelData.description || device.modelData.nickname || device.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        color: device.current ? Theme.text : Theme.subtext
                    }

                    Icon {
                        id: check
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "check"
                        font.pixelSize: 18
                        color: Theme.accent
                        opacity: device.current ? 1 : 0
                        scale: device.current ? 1 : 0.4
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                        Behavior on scale { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Pipewire.preferredDefaultAudioSink = device.modelData
                    }
                }
            }
        }
    }

    component Channel: Column {
        id: ch

        property PwNode node
        property var icons
        property string title
        readonly property real volume: node?.audio?.volume ?? 0
        readonly property bool muted: node?.audio?.muted ?? false
        readonly property bool pressed: slider.pressed

        visible: !!node
        width: parent.width
        spacing: 8

        Item {
            width: parent.width
            height: 30

            Rectangle {
                id: muteBtn

                width: 30
                height: 30
                radius: 15
                color: ch.muted ? Theme.surface : Qt.tint(Theme.bg, Qt.alpha(Theme.accent, muteMouse.containsMouse ? 0.22 : 0.14))
                Behavior on color { ColorAnimation { duration: Theme.anim } }

                Icon {
                    anchors.centerIn: parent
                    text: ch.muted || ch.volume === 0 ? ch.icons[0]
                        : ch.volume < 0.34 ? ch.icons[1]
                        : ch.volume < 0.67 ? ch.icons[2]
                        : ch.icons[3]
                    font.pixelSize: 18
                    color: ch.muted ? Theme.subtext : Theme.accent
                }

                MouseArea {
                    id: muteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ch.node.audio.muted = !ch.muted
                }
            }

            Label {
                anchors.left: muteBtn.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: ch.title
                font.pixelSize: 14
            }

            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ch.muted ? "Muted" : Math.round(ch.volume * 100) + "%"
                font.pixelSize: 13
                color: Theme.subtext
            }
        }

        Slider {
            id: slider
            width: parent.width
            value: ch.volume
            dim: ch.muted
            onMoved: v => {
                ch.node.audio.volume = v;
                if (ch.muted && v > 0)
                    ch.node.audio.muted = false;
            }
        }
    }
}
