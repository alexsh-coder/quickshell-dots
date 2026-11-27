import QtQuick
import qs.config
import qs.components
import qs.services

// Actions for one app, opened by right click or the Menu key
Rectangle {
    id: root

    property var items: []
    property int current: -1
    property bool open: false
    // Opens upwards when there's no room below
    property bool flipped: false

    signal triggered(string action)

    width: 220
    height: column.implicitHeight + 12
    radius: Theme.radius
    color: Theme.surface
    border.width: 1
    border.color: Qt.alpha(Theme.accent, 0.25)

    visible: opacity > 0
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.92
    transformOrigin: flipped ? Item.BottomLeft : Item.TopLeft
    Behavior on opacity { NumberAnimation { duration: root.open ? Theme.anim : 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: root.open ? Theme.anim : 120; easing.type: Easing.OutCubic } }

    // Clicks on the padding don't fall through and close the menu
    MouseArea {
        anchors.fill: parent
    }

    Column {
        id: column
        x: 6
        y: 6
        width: parent.width - 12

        Repeater {
            model: root.items

            MouseArea {
                id: item
                onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                onReleased: if (containsMouse) Sfx.tap("click")

                required property var modelData
                required property int index
                readonly property bool current: root.current === index

                width: column.width
                height: 36
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.current = index
                onClicked: root.triggered(modelData.action)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius - 4
                    color: Qt.alpha(Theme.accent, 0.14)
                    opacity: item.current ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                Icon {
                    id: icon
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.modelData.icon
                    font.pixelSize: 18
                    color: item.current ? Theme.accent : Theme.subtext
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Label {
                    anchors.left: icon.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 14
                    text: item.modelData.text
                    color: item.current ? Theme.accent : Theme.text
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 12
                    font.weight: Font.Normal
                    text: item.modelData.hint
                    color: Theme.subtext
                }
            }
        }
    }
}
