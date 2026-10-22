import QtQuick
import qs.config
import qs.modules.lock

// Big clock: one line, hours over minutes, or time over the date. Digits roll like the lock screen's
DeskFit {
    id: root

    property var cfg: ({})
    property date now: new Date()
    readonly property color ink: cfg.card && cfg.color === "auto" ? Theme.text : Theme.paint(cfg.color)
    readonly property int weight: ({ light: Font.Light, regular: Font.Normal, bold: Font.Bold })[cfg.weight] ?? Font.Light
    readonly property string hh: Qt.formatTime(now, "hh")
    readonly property string mm: Qt.formatTime(now, "mm")
    readonly property string ss: Qt.formatTime(now, "ss")

    align: cfg.align ?? "center"
    card: !!cfg.card
    tint: ink

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Column {
        spacing: root.cfg.style === "date" ? 4 : -40

        // Time; for "stack", hours over minutes
        Repeater {
            model: root.cfg.style === "stack" ? [root.hh, root.mm] : [root.hh + ":" + root.mm + (root.cfg.seconds ? ":" + root.ss : "")]

            Row {
                required property string modelData

                anchors.left: root.align === "left" ? parent?.left : undefined
                anchors.right: root.align === "right" ? parent?.right : undefined
                anchors.horizontalCenter: root.align === "center" ? parent?.horizontalCenter : undefined

                Repeater {
                    model: parent.modelData.split("")

                    Digit {
                        required property string modelData

                        value: modelData
                        color: root.ink
                        font.family: Theme.font
                        font.pixelSize: 200
                        font.weight: root.weight
                        font.features: ({ tnum: 1 })
                    }
                }
            }
        }

        Text {
            visible: root.cfg.style === "date"
            anchors.left: root.align === "left" ? parent.left : undefined
            anchors.right: root.align === "right" ? parent.right : undefined
            anchors.horizontalCenter: root.align === "center" ? parent.horizontalCenter : undefined
            text: root.now.toLocaleDateString(Qt.locale("en_US"), "dddd, d MMMM")
            color: Qt.alpha(root.ink, 0.8)
            font.family: Theme.font
            font.pixelSize: 54
            font.weight: root.weight === Font.Bold ? Font.DemiBold : Font.Normal
        }
    }
}
