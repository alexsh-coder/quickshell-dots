import QtQuick
import QtQuick.Shapes
import qs.config
import qs.services

// CPU, RAM and GPU load as rings or bars (see SystemStats)
DeskFit {
    id: root

    property var cfg: ({})
    readonly property color ink: cfg.card && cfg.color === "auto" ? Theme.text : Theme.paint(cfg.color)
    readonly property color mark: cfg.color === "auto" ? Theme.accent : ink
    readonly property var items: [
        { label: "CPU", value: SystemStats.cpu },
        { label: "RAM", value: SystemStats.ram },
        { label: "GPU", value: SystemStats.gpu }
    ].filter(i => i.value >= 0)

    card: !!cfg.card
    tint: ink

    Component.onCompleted: SystemStats.users++
    Component.onDestruction: SystemStats.users--

    // A Loader, so only the shown layout counts towards the size
    Loader {
        sourceComponent: root.cfg.style === "bars" ? bars : rings
    }

    Component {
        id: rings

        Row {
            spacing: 40

            // By count: the values refresh every poll, delegates shouldn't be rebuilt for that
            Repeater {
                model: root.items.length

                Item {
                    id: ring

                    required property int index
                    readonly property var modelData: root.items[index] ?? ({ label: "", value: 0 })

                    width: 150
                    height: 150

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: Qt.alpha(root.ink, 0.2)
                            strokeWidth: 12
                            capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 75; centerY: 75; radiusX: 66; radiusY: 66; startAngle: 0; sweepAngle: 360 }
                        }

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: root.mark
                            strokeWidth: 12
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 75
                                centerY: 75
                                radiusX: 66
                                radiusY: 66
                                startAngle: -90
                                sweepAngle: 360 * Math.max(0.01, ring.modelData.value)
                                Behavior on sweepAngle { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(ring.modelData.value * 100) + "%"
                            color: root.ink
                            font.family: Theme.font
                            font.pixelSize: 36
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ring.modelData.label
                            color: Qt.alpha(root.ink, 0.65)
                            font.family: Theme.font
                            font.pixelSize: 22
                        }
                    }
                }
            }
        }

    }

    Component {
        id: bars

        Column {
            spacing: 18

            Repeater {
                model: root.items.length

                Row {
                    id: line

                    required property int index
                    readonly property var modelData: root.items[index] ?? ({ label: "", value: 0 })

                    spacing: 20

                    Text {
                        width: 80
                        anchors.verticalCenter: parent.verticalCenter
                        text: line.modelData.label
                        color: Qt.alpha(root.ink, 0.7)
                        font.family: Theme.font
                        font.pixelSize: 28
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 360
                        height: 14
                        radius: 7
                        color: Qt.alpha(root.ink, 0.2)

                        Rectangle {
                            width: Math.max(parent.height, parent.width * line.modelData.value)
                            height: parent.height
                            radius: parent.radius
                            color: root.mark
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        width: 90
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(line.modelData.value * 100) + "%"
                        color: root.ink
                        font.family: Theme.font
                        font.pixelSize: 28
                        font.features: ({ tnum: 1 })
                    }
                }
            }
        }
    }
}
