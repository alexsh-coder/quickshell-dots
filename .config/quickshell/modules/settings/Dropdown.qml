import QtQuick
import QtQuick.Controls as QQC
import qs.config
import qs.components
import qs.services

// One of many choices in a list that drops down: model is [{ value, label }], current the value picked
Rectangle {
    id: root

    property var model: []
    property var current
    property real minWidth: 160
    signal picked(var value)

    readonly property var currentItem: (model ?? []).find(m => m.value === current) ?? null

    implicitWidth: Math.max(minWidth, measure.implicitWidth + 24 + 28)
    implicitHeight: 34
    radius: height / 2
    color: popup.opened ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.22))
        : area.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    // Widest label, so the button keeps its size whatever is picked
    Column {
        id: measure
        visible: false
        Repeater {
            model: root.model
            Label {
                required property var modelData
                text: modelData.label
                font.pixelSize: 13
            }
        }
    }

    Label {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentItem?.label ?? "—"
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    Icon {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: "expand_more"
        font.pixelSize: 18
        color: Theme.subtext
        rotation: popup.opened ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
        onClicked: {
            Sfx.tap("click");
            if (popup.opened)
                popup.close();
            else
                popup.open();
        }
    }

    QQC.Popup {
        id: popup

        readonly property int rowHeight: 32
        readonly property int maxRows: 8

        y: root.height + 6
        width: Math.max(root.width, measure.implicitWidth + 48)
        height: Math.min(root.model?.length ?? 0, maxRows) * rowHeight + 12
        padding: 6
        focus: true
        closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside

        onOpened: list.positionViewAtIndex(Math.max(0, (root.model ?? []).indexOf(root.currentItem)), ListView.Center)

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim * 0.7 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.anim; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.anim * 0.5 }
        }

        background: Rectangle {
            radius: Theme.radius
            color: Theme.surface
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.25)
        }

        contentItem: ListView {
            id: list

            clip: true
            model: root.model
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                readonly property bool on: root.current === modelData.value

                width: ListView.view.width
                height: popup.rowHeight
                radius: Theme.radius - 4
                color: on ? Qt.alpha(Theme.accent, 0.22) : rowArea.containsMouse ? Qt.alpha(Theme.accent, 0.1) : "transparent"

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: check.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    font.pixelSize: 13
                    color: row.on ? Theme.accent : Theme.text
                    elide: Text.ElideRight
                }

                Icon {
                    id: check
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.on
                    text: "check"
                    font.pixelSize: 16
                    color: Theme.accent
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                    onClicked: {
                        Sfx.tap("click");
                        popup.close();
                        root.picked(row.modelData.value);
                    }
                }
            }
        }
    }
}
