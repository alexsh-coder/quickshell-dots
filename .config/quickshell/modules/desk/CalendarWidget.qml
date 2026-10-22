import QtQuick
import qs.config

// This month, Monday first, today in the accent
DeskFit {
    id: root

    property var cfg: ({})
    property date today: new Date()
    readonly property color ink: cfg.card && cfg.color === "auto" ? Theme.text : Theme.paint(cfg.color)
    readonly property color mark: cfg.color === "auto" ? Theme.accent : ink
    readonly property int cell: 64
    readonly property var cells: {
        const y = today.getFullYear(), m = today.getMonth();
        const first = new Date(y, m, 1);
        const start = new Date(y, m, 1 - (first.getDay() + 6) % 7);
        const out = [];
        for (let i = 0; i < 42; i++)
            out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return out;
    }

    card: !!cfg.card
    tint: ink

    // Rolls over at midnight
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            const d = new Date();
            if (d.getDate() !== root.today.getDate())
                root.today = d;
        }
    }

    Column {
        spacing: 12

        Text {
            x: 10
            text: root.today.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
            color: root.ink
            font.family: Theme.font
            font.pixelSize: 34
            font.weight: Font.DemiBold
        }

        Grid {
            columns: 7

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

                Text {
                    required property string modelData
                    width: root.cell
                    height: 44
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Qt.alpha(root.ink, 0.6)
                    font.family: Theme.font
                    font.pixelSize: 22
                }
            }

            Repeater {
                model: root.cells

                Item {
                    id: day

                    required property date modelData
                    readonly property bool inMonth: modelData.getMonth() === root.today.getMonth()
                    readonly property bool isToday: inMonth && modelData.getDate() === root.today.getDate()

                    width: root.cell
                    height: root.cell

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: width
                        radius: width / 2
                        color: root.mark
                        visible: day.isToday
                    }

                    Text {
                        anchors.centerIn: parent
                        text: day.modelData.getDate()
                        color: day.isToday ? (root.mark.hslLightness > 0.6 ? "#000000" : "#ffffff") : Qt.alpha(root.ink, day.inMonth ? 1 : 0.3)
                        font.family: Theme.font
                        font.pixelSize: 26
                        font.weight: day.isToday ? Font.Bold : Font.Normal
                        font.features: ({ tnum: 1 })
                    }
                }
            }
        }
    }
}
