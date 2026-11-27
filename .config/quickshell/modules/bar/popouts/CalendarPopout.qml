import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property int cell: 38
    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    property bool editing: false

    // Monday-first grid of 6 weeks around the shown month
    readonly property var cells: {
        const first = new Date(year, month, 1);
        const start = new Date(year, month, 1 - (first.getDay() + 6) % 7);
        const out = [];
        for (let i = 0; i < 42; i++)
            out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return out;
    }

    function shift(step) {
        const d = new Date(year, month + step, 1);
        year = d.getFullYear();
        month = d.getMonth();
        slide.from = step * 28;
        slide.restart();
    }

    function edit(on) {
        editing = on;
        popouts.pinned = on;
    }

    implicitWidth: cell * 7 + Theme.pad * 2
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    onHereChanged: {
        if (here) {
            today = new Date();
            year = today.getFullYear();
            month = today.getMonth();
            Weather.refresh();
        } else if (editing) {
            edit(false);
        }
    }

    Connections {
        target: root.popouts
        function onPinnedChanged() {
            if (!root.popouts.pinned)
                root.editing = false;
        }
    }

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 12

        Item {
            width: parent.width
            height: 30

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: 4
                text: Qt.locale("en_US").standaloneMonthName(root.month) + " " + root.year
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                RoundButton { icon: "chevron_left"; onClicked: root.shift(-1) }
                RoundButton { icon: "chevron_right"; onClicked: root.shift(1) }
            }
        }

        Item {
            width: parent.width
            height: week.height + grid.height
            clip: true

            Row {
                id: week
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Label {
                        required property string modelData
                        required property int index
                        width: root.cell
                        height: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: 12
                        color: index >= 5 ? Qt.alpha(Theme.accent, 0.8) : Theme.subtext
                    }
                }
            }

            Grid {
                id: grid

                y: week.height
                columns: 7
                transform: Translate { id: slideShift }

                ParallelAnimation {
                    id: slide
                    property real from: 0
                    NumberAnimation { target: slideShift; property: "x"; from: slide.from; to: 0; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial }
                    NumberAnimation { target: grid; property: "opacity"; from: 0; to: 1; duration: Theme.anim; easing.type: Easing.OutCubic }
                }

                Repeater {
                    model: root.cells

                    Item {
                        required property date modelData
                        readonly property bool inMonth: modelData.getMonth() === root.month
                        readonly property bool isToday: modelData.toDateString() === root.today.toDateString()

                        width: root.cell
                        height: root.cell - 6

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: 15
                            color: Theme.accent
                            visible: parent.isToday
                        }

                        Label {
                            anchors.centerIn: parent
                            text: parent.modelData.getDate()
                            font.pixelSize: 13
                            font.weight: parent.isToday ? Font.Bold : Font.Medium
                            color: parent.isToday ? Theme.bg : parent.inMonth ? Theme.text : Theme.muted
                        }
                    }
                }
            }

            WheelHandler {
                onWheel: event => root.shift(event.angleDelta.y < 0 ? 1 : -1)
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.muted
        }

        // Current weather
        Item {
            width: parent.width
            height: 48

            Icon {
                id: wIcon
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.current ? Weather.icon(Weather.current.code, Weather.current.day) : "cloud_off"
                font.pixelSize: 40
                fill: 0
                color: Theme.accent
            }

            Column {
                anchors.left: wIcon.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Label {
                    text: Weather.current ? Weather.current.temp + "°" : "--"
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Label {
                    text: Weather.current ? Weather.describe(Weather.current.code) : Weather.loading ? "Loading…" : "No data"
                    font.pixelSize: 12
                    color: Theme.subtext
                }
            }

            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // Click to type a city
                Item {
                    anchors.right: parent.right
                    width: root.editing ? 150 : place.implicitWidth + 20
                    height: 22

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: 8
                        color: Theme.surface
                        border.width: root.editing ? 1 : 0
                        border.color: Theme.accent
                        opacity: root.editing || placeMouse.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }

                    Row {
                        visible: !root.editing
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "location_on"
                            font.pixelSize: 15
                            fill: 0
                            color: Theme.subtext
                        }
                        Label {
                            id: place
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.failed && Weather.city ? Weather.city + "?" : Weather.place || "Set city"
                            font.pixelSize: 12
                            color: Weather.failed ? Theme.urgent : Theme.subtext
                        }
                    }

                    MouseArea {
                        id: placeMouse
                        onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                        onPressedChanged: if (pressed) Sfx.play("clickPop")
                        anchors.fill: parent
                        visible: !root.editing
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.edit(true)
                    }

                    TextInput {
                        id: cityField

                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        visible: root.editing
                        enabled: root.editing
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.text
                        selectionColor: Qt.alpha(Theme.accent, 0.4)
                        clip: true

                        onEnabledChanged: if (enabled) {
                            text = Weather.city;
                            selectAll();
                            forceActiveFocus();
                        }
                        onAccepted: {
                            Weather.setCity(text);
                            root.edit(false);
                        }
                        Keys.onEscapePressed: root.edit(false)

                        Label {
                            visible: !cityField.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: "City, empty = auto"
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }
                }

                Label {
                    anchors.right: parent.right
                    visible: !!Weather.current
                    text: Weather.current ? `feels ${Weather.current.feels}° · ${Weather.current.wind} km/h` : ""
                    font.pixelSize: 11
                    color: Theme.subtext
                }
            }
        }

        // Next days
        Row {
            visible: Weather.days.length > 0
            width: parent.width

            Repeater {
                model: Weather.days

                Column {
                    required property var modelData
                    required property int index

                    width: content.width / Weather.days.length
                    spacing: 4

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.index === 0 ? "Today" : Qt.locale("en_US").dayName(parent.modelData.date.getDay(), Locale.ShortFormat)
                        font.pixelSize: 11
                        color: parent.index === 0 ? Theme.accent : Theme.subtext
                    }
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.icon(parent.modelData.code, true)
                        font.pixelSize: 22
                        fill: 0
                        color: Theme.text
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.modelData.max + "°"
                        font.pixelSize: 12
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.modelData.min + "°"
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                }
            }
        }
    }

    component RoundButton: Rectangle {
        id: btn

        property string icon
        signal clicked

        width: 28
        height: 28
        radius: 14
        color: btnMouse.containsMouse ? Theme.surface : Theme.bg
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Icon {
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: 20
            color: Theme.subtext
        }

        MouseArea {
            id: btnMouse
            onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
            onPressedChanged: if (pressed) Sfx.play("clickPop")
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
