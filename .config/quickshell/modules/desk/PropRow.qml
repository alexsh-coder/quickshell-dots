import QtQuick
import qs.config
import qs.services
import qs.components

// One setting from a schema (see Desk.kinds): a slider for numbers, chips for choices, a switch for bools
Column {
    id: root

    required property var row
    property var value
    // The default; when the value differs a reset button shows
    property var initial: undefined
    readonly property bool changed: initial !== undefined && JSON.stringify(value) !== JSON.stringify(initial)
    signal reset
    readonly property bool numeric: row.min !== undefined
    signal edited(var v)

    function show() {
        if (row.unit === "%")
            return Math.round(value * 100) + "%";
        if (row.unit === "°")
            return (value > 0 ? "+" : "") + Math.round(value) + "°";
        return (+(+value).toFixed(2)) + (row.unit ?? "");
    }

    spacing: 6

    Item {
        width: parent.width
        height: 24

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.row.label
            font.pixelSize: 13
            color: Theme.subtext
        }

        Rectangle {
            visible: root.changed
            anchors.right: parent.right
            anchors.rightMargin: root.row.type === "bool" ? 48 : root.numeric ? valueLabel.implicitWidth + 8 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: 11
            color: resetArea.containsMouse ? Theme.muted : "transparent"

            Icon {
                anchors.centerIn: parent
                text: "restart_alt"
                font.pixelSize: 16
                color: Theme.subtext
            }

            MouseArea {
                onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                onReleased: if (containsMouse) Sfx.tap("click")
                id: resetArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reset()
            }
        }

        Label {
            id: valueLabel
            visible: root.numeric
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.numeric ? root.show() : ""
            font.pixelSize: 13
        }

        Toggle {
            visible: root.row.type === "bool"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: !!root.value
            onToggled: root.edited(!root.value)
        }
    }

    Slider {
        visible: root.numeric
        width: parent.width
        value: root.numeric ? (root.value - root.row.min) / (root.row.max - root.row.min) : 0
        onMoved: v => {
            const r = root.row;
            const x = Math.round((r.min + v * (r.max - r.min)) / r.step) * r.step;
            root.edited(+Math.max(r.min, Math.min(r.max, x)).toFixed(4));
        }
    }

    Flow {
        visible: !!root.row.values
        width: parent.width
        spacing: 6

        Repeater {
            model: root.row.values ?? []

            Chip {
                required property string modelData
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                // Multi rows hold a list: chips toggle their value in or out
                readonly property var list: [].concat(root.value ?? [])
                on: root.row.multi ? list.includes(modelData) : root.value === modelData
                onClicked: root.edited(root.row.multi ? (on ? list.filter(v => v !== modelData) : list.concat([modelData])) : modelData)
            }
        }
    }
}
