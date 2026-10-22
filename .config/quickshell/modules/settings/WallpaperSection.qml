import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services
import qs.modules.wallpaper

// Transition gallery: every style plays on loop between the wallpaper and another from its folder
Column {
    id: root

    property bool shown: false

    readonly property int columns: 4
    readonly property int gap: 10
    readonly property real tileWidth: (width - gap * (columns - 1)) / columns
    readonly property real tileHeight: Math.round(tileWidth * 0.62)

    // The two pictures the previews swap between, and which one is on top this round
    property string first: Wallpaper.image
    property string second: Wallpaper.image
    property bool flip: false
    property int round: 0
    property real t: 0

    spacing: 6

    onShownChanged: if (shown) others.running = true

    Process {
        id: others
        command: ["find", Wallpaper.image.replace(/\/[^/]*$/, ""), "-maxdepth", "1", "-type", "f",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(p => p && p !== Wallpaper.image);
                root.first = Wallpaper.image;
                root.second = list.length ? list[Math.floor(Math.random() * list.length)] : Wallpaper.image;
            }
        }
    }

    // Plays each transition, holds the result for a moment, then plays it back the other way
    SequentialAnimation {
        running: root.shown && root.visible
        loops: Animation.Infinite

        NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: Settings.transitionTime }
        PauseAnimation { duration: 900 }
        ScriptAction { script: { root.flip = !root.flip; root.round++; root.t = 0; } }
    }

    Image {
        id: picA
        visible: false
        width: root.tileWidth
        height: root.tileHeight
        source: root.first ? "file://" + root.first : ""
        sourceSize: Qt.size(480, 300)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    Image {
        id: picB
        visible: false
        width: root.tileWidth
        height: root.tileHeight
        source: root.second ? "file://" + root.second : ""
        sourceSize: Qt.size(480, 300)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    SectionTitle { text: "Transition" }

    Label {
        width: parent.width
        text: "How a new wallpaper replaces the old one, from the picker or Super+Alt+[ and ]"
        font.pixelSize: 12
        color: Theme.subtext
        wrapMode: Text.Wrap
        bottomPadding: 6
    }

    Grid {
        columns: root.columns
        spacing: root.gap

        Repeater {
            model: Wallpaper.transitions.concat([{ name: "random", label: "Random", icon: "shuffle" }])

            Item {
                id: tile

                required property var modelData
                required property int index
                readonly property bool on: Settings.transition === modelData.name
                readonly property bool random: modelData.name === "random"

                width: root.tileWidth
                height: root.tileHeight + 26

                Rectangle {
                    id: frame

                    width: parent.width
                    height: root.tileHeight
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: tile.on ? 2 : 0
                    border.color: Theme.accent
                    scale: area.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }

                    Item {
                        id: view

                        anchors.fill: parent
                        anchors.margins: tile.on ? 3 : 0
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: corners
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }

                        Image {
                            anchors.fill: parent
                            source: (root.flip ? picB : picA).source
                            sourceSize: Qt.size(480, 300)
                            fillMode: Image.PreserveAspectCrop
                        }

                        TransitionEffect {
                            anchors.fill: parent
                            source: root.flip ? picA : picB
                            previous: root.flip ? picB : picA
                            hasPrevious: true
                            cropTo: cropOf(root.flip ? picA : picB)
                            cropFrom: cropOf(root.flip ? picB : picA)
                            t: root.t
                            // Random shows each style in turn
                            effect: tile.random ? root.round % Wallpaper.transitions.length : tile.index
                            origin: "right"
                        }
                    }

                    Rectangle {
                        id: corners
                        anchors.fill: view
                        radius: Theme.radius - (tile.on ? 3 : 0)
                        visible: false
                        layer.enabled: true
                    }
                }

                Row {
                    anchors.top: frame.bottom
                    anchors.topMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.modelData.icon
                        font.pixelSize: 15
                        fill: tile.on ? 1 : 0
                        color: tile.on ? Theme.accent : Theme.subtext
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.modelData.label
                        font.pixelSize: 12
                        font.weight: tile.on ? Font.DemiBold : Font.Medium
                        color: tile.on ? Theme.accent : Theme.text
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Settings.transition = tile.modelData.name
                }
            }
        }
    }

    SettingRow {
        label: "Duration"

        ValueSlider {
            from: 0.3
            to: 2.5
            step: 0.1
            value: Settings.transitionTime / 1000
            format: v => v.toFixed(1) + " s"
            onMoved: v => Settings.transitionTime = Math.round(v * 1000)
        }
    }

    SectionTitle { text: "Slideshow" }

    SettingRow {
        label: "Change wallpaper every"
        hint: "Picks a random one from the folder last shown in the picker"

        Chips {
            current: Settings.slideshow
            model: [
                { value: 0, label: "Off" },
                { value: 5, label: "5 min" },
                { value: 15, label: "15 min" },
                { value: 30, label: "30 min" },
                { value: 60, label: "1 h" }
            ]
            onPicked: v => Settings.slideshow = v
        }
    }
}
