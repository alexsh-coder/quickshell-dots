import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

MouseArea {
    id: root

    required property DesktopEntry modelData
    required property int index
    required property var launcher
    property bool pinned: false
    property bool hidden: false
    property bool current: false
    readonly property alias iconItem: icon
    readonly property bool renaming: launcher.renaming !== "" && launcher.renaming === modelData?.id
    onRenamingChanged: {
        if (!renaming)
            return;
        nameInput.text = launcher.renameText;
        nameInput.forceActiveFocus();
        nameInput.selectAll();
    }
    // Vertical offset for the entrance hop; a transform so it doesn't fight ListView's y
    property real lift: 0
    // Pinned row picked up by a long press or by moving while pressed (touchpad tap-and-drag gives no pause)
    // follows the cursor; dragged survives until the next press to eat the click.
    // The rows it passes step aside by shift.
    property bool held: false
    property bool dragged: false
    property real grabY: 0
    property real dragOffset: 0
    property real shift: 0
    readonly property real shiftTarget: launcher.dragShift(index)
    onShiftTargetChanged: {
        if (launcher.dropping)
            return;
        shiftAnim.to = shiftTarget;
        shiftAnim.restart();
    }

    NumberAnimation {
        id: shiftAnim
        target: root
        property: "shift"
        duration: Theme.anim
        easing.type: Easing.OutCubic
    }

    // Right before the drop reorders the model: the new y takes over the step aside,
    // so only what's left of it in flight carries on and fades out
    Connections {
        target: root.launcher
        function onDroppingChanged() {
            if (!root.launcher.dropping)
                return;
            shiftAnim.stop();
            root.shift -= root.shiftTarget;
            shiftAnim.to = 0;
            shiftAnim.restart();
        }
    }

    transform: [
        Translate { y: root.lift },
        Translate { y: root.dragOffset + root.shift },
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: root.held ? 1.03 : 1
            yScale: xScale
            Behavior on xScale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }
        }
    ]
    z: held ? 10 : 0

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    pressAndHoldInterval: 300
    // Pinned rows keep the press from the list's flick so a drag can start
    preventStealing: held || pinned && !launcher.query.trim()
    cursorShape: held ? Qt.ClosedHandCursor : Qt.ArrowCursor

    function follow() {
        if (held)
            dragOffset = launcher.dragTop - y;
    }

    onYChanged: follow()

    NumberAnimation {
        id: settle
        target: root
        property: "dragOffset"
        to: 0
        duration: Theme.anim
        easing.type: Easing.OutCubic
        // Whatever stops it, a row nobody holds ends up in its slot
        onStopped: if (!root.held) root.dragOffset = 0
    }

    onPressed: event => {
        dragged = false;
        grabY = event.y;
    }
    function pickUp() {
        if (!launcher.startDrag(modelData, index))
            return;
        settle.stop();
        held = true;
        dragged = true;
        launcher.dragTo(y);
        follow();
    }

    onPressAndHold: event => {
        if (event.button === Qt.LeftButton && !dragged)
            pickUp();
    }
    function drop() {
        if (!held)
            return;
        // follow() runs through the reorder, so the offset is rebased onto the new y
        launcher.endDrag();
        follow();
        held = false;
        settle.restart();
    }

    onReleased: drop()
    onCanceled: drop()
    onPositionChanged: mouse => {
        if (!held && !dragged && (pressedButtons & Qt.LeftButton) && Math.abs(mouse.y - grabY) > Application.styleHints.startDragDistance)
            pickUp();
        if (held) {
            launcher.dragTo(mapToItem(ListView.view.contentItem, mouse.x, mouse.y).y - grabY);
            follow();
            return;
        }
        if (!launcher.cursorMoved(root, mouse.x, mouse.y) || launcher.renaming)
            return;
        ListView.view.currentIndex = index;
    }
    onClicked: event => {
        if (dragged)
            return;
        if (launcher.renaming)
            launcher.commitRename();
        else if (event.button === Qt.RightButton)
            launcher.openMenu(modelData, mapToItem(null, event.x, event.y));
        else
            launcher.launch(modelData);
    }

    // Lifted card under the dragged row; the list's highlight marks where it will drop
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.4)
        opacity: root.held ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    AppIcon {
        id: icon
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: 32
        opacity: root.hidden ? 0.4 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        icon: root.modelData?.icon ?? ""
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: pin.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        opacity: root.hidden ? 0.4 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        Label {
            visible: !root.renaming
            width: parent.width
            elide: Text.ElideRight
            text: Names.name(root.modelData)
            color: root.current ? Theme.accent : Theme.text
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        TextInput {
            id: nameInput
            visible: root.renaming
            width: parent.width
            font.family: Theme.font
            font.pixelSize: 15
            font.weight: Font.Medium
            color: Theme.accent
            selectionColor: Qt.alpha(Theme.accent, 0.4)
            selectedTextColor: Theme.text
            clip: true
            onTextEdited: root.launcher.renameText = text
            // Losing focus to a click elsewhere keeps the new name
            onActiveFocusChanged: if (!activeFocus && root.renaming) root.launcher.commitRename()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    root.launcher.commitRename();
                else if (event.key === Qt.Key_Escape)
                    root.launcher.cancelRename();
                else if (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down && event.key !== Qt.Key_Tab)
                    return;
                event.accepted = true;
            }
        }

        Label {
            visible: text
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: 12
            font.weight: Font.Normal
            text: root.modelData?.comment || root.modelData?.genericName || ""
            color: Theme.subtext
        }
    }

    Icon {
        id: pin
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "push_pin"
        font.pixelSize: 18
        color: Theme.accent
        opacity: root.pinned ? 1 : 0
        scale: root.pinned ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }
    }

    Icon {
        anchors.centerIn: pin
        text: "visibility_off"
        font.pixelSize: 18
        color: Theme.subtext
        opacity: root.hidden && !root.pinned ? 1 : 0
        scale: root.hidden && !root.pinned ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }
    }
}
