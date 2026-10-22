import QtQuick
import qs.config
import qs.components
import qs.services

// Open-Meteo weather (see Weather): now, or the next three days
DeskFit {
    id: root

    property var cfg: ({})
    readonly property var now: Weather.current
    readonly property color ink: cfg.card && cfg.color === "auto" ? Theme.text : Theme.paint(cfg.color)

    card: !!cfg.card
    tint: ink
    opacity: now ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

    Component.onCompleted: Weather.refresh()

    // A Loader, so only the shown layout counts towards the size
    Loader {
        sourceComponent: root.cfg.style === "days" ? days : today
    }

    // Now: icon, temperature, sky and place
    Component {
        id: today

        Row {
            spacing: 24

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.now ? Weather.icon(root.now.code, root.now.day) : ""
                color: root.ink
                font.pixelSize: 140
                fill: 1
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: root.now ? root.now.temp + "°" : ""
                    color: root.ink
                    font.family: Theme.font
                    font.pixelSize: 110
                    font.weight: Font.Light
                }

                Text {
                    text: root.now ? Weather.describe(root.now.code) + (Weather.place ? " · " + Weather.place : "") : ""
                    color: Qt.alpha(root.ink, 0.75)
                    font.family: Theme.font
                    font.pixelSize: 30
                }
            }
        }

    }

    // Three days: weekday, icon, high and low
    Component {
        id: days

        Row {
            spacing: 48

            Repeater {
                model: Weather.days.slice(0, 3)

                Column {
                    required property var modelData
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.date.toLocaleDateString(Qt.locale("en_US"), "ddd")
                        color: Qt.alpha(root.ink, 0.75)
                        font.family: Theme.font
                        font.pixelSize: 30
                    }

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.icon(modelData.code, true)
                        color: root.ink
                        font.pixelSize: 96
                        fill: 1
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.max + "° " + "<font color='" + Qt.alpha(root.ink, 0.55) + "'>" + modelData.min + "°</font>"
                        textFormat: Text.StyledText
                        color: root.ink
                        font.family: Theme.font
                        font.pixelSize: 34
                    }
                }
            }
        }
    }
}
