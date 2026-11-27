import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Window
import qs.config
import qs.components
import qs.services

// One of many choices in a list that drops down: model is [{ value, label }], current the value picked
Rectangle {
    id: root

    property var model: []
    property var current
    property real minWidth: 160
    // Rows call hovered() instead of the usual hover sound, e.g. to play the sound they name
    property bool hoverPreview: false
    // current is a list and rows tick on and off; the empty value clears it
    property bool multi: false
    signal picked(var value)
    signal hovered(var value)
    // The closed button with hoverPreview on
    signal buttonHovered()

    // Several picked show up as their labels in a row
    readonly property var currentItem: {
        const all = model ?? [];
        if (!multi)
            return all.find(m => m.value === current) ?? null;
        const on = Array.from(current ?? []);
        if (!on.length)
            return all.find(m => m.value === "") ?? null;
        return { label: on.map(v => all.find(m => m.value === v)?.label ?? v).join(", ") };
    }
    function isOn(v) {
        return multi ? ((current ?? []).length ? current.includes(v) : v === "") : current === v;
    }

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
        onContainsMouseChanged: if (containsMouse) root.hoverPreview ? root.buttonHovered() : Sfx.play("hover")
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

        // Opens upward when there's no room below the button
        property bool up: false
        y: up ? -height - 6 : root.height + 6
        onAboutToShow: {
            const below = (root.Window.height || 0) - root.mapToItem(null, 0, root.height).y;
            const above = root.mapToItem(null, 0, 0).y;
            up = below < height + 12 && above > below;
        }
        width: Math.max(root.width, measure.implicitWidth + 48)
        height: Math.min(root.model?.length ?? 0, maxRows) * rowHeight + 12
        padding: 6
        focus: true
        closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutsideParent

        onOpened: list.positionViewAtIndex(Math.max(0, (root.model ?? []).findIndex(m => root.isOn(m.value))), ListView.Center)

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
                readonly property bool on: root.isOn(modelData.value)

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
                    onContainsMouseChanged: {
                        if (!containsMouse)
                            return;
                        if (root.hoverPreview)
                            root.hovered(row.modelData.value);
                        else
                            Sfx.play("hover");
                    }
                    onClicked: {
                        if (!root.hoverPreview)
                            Sfx.tap("click");
                        if (!root.multi || row.modelData.value === "")
                            popup.close();
                        root.picked(row.modelData.value);
                    }
                }
            }
        }
    }
}
