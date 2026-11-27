import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// Notification history sliding in from the right edge. Opens by hotkey or
// from a small tab that peeks out when the pointer touches the edge;
// closes on Esc or a click outside
Scope {
    id: root

    onOpenChanged: Sfx.play(open ? "open" : "close")

    property bool open: false
    property ShellScreen screen: Quickshell.screens[0]

    readonly property int gap: 10
    readonly property int cardWidth: 380
    // Hot zone along the right edge, as a share of the screen height
    readonly property real edgeSpan: 0.4

    function show(target) {
        screen = target ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        open = true;
        Notifs.hidePopups();
    }

    function hide() {
        open = false;
        sweep.stop();
    }

    function toggle() {
        if (open)
            hide();
        else
            show(null);
    }

    Binding {
        target: Notifs
        property: "centerOpen"
        value: root.open
    }

    // Clear all: cards fly out one by one from the bottom up, so nothing
    // above them has to move. Cards scrolled out of view go at once
    property var sweepQueue: []

    function clearAll() {
        const view = panelLoader.item?.list ?? null;
        const entries = Notifs.list.slice();
        const last = view ? view.indexAt(view.width / 2, view.contentY + view.height - 1) : -1;
        const shown = last < 0 ? entries.length : last + 1;
        for (const n of entries.slice(shown))
            n.close();
        sweepQueue = entries.slice(0, shown);
        sweep.start();
    }

    Timer {
        id: sweep
        interval: 45
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const n = root.sweepQueue.pop();
            if (n)
                n.close();
            else {
                stop();
                autoHide.start();
            }
        }
    }

    Timer {
        id: autoHide
        interval: 300
        onTriggered: root.hide()
    }

    GlobalShortcut {
        name: "notifcenter"
        description: "Toggle the notification center"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "notifcenter"

        function toggle(): void {
            root.toggle();
        }
    }

    // Hot edge: a 1px strip in the middle of every screen's right side.
    // Touching it slides a tab out; clicking the tab opens the center.
    // On the Top layer, so fullscreen windows cover it
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: edge

            required property var modelData
            property bool peek: false
            readonly property bool out: peek && !root.open

            screen: modelData
            WlrLayershell.namespace: "qs-edge"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal
            anchors.right: true
            implicitWidth: 64
            implicitHeight: Math.round(modelData.height * root.edgeSpan)
            color: "transparent"
            mask: Region {
                item: strip
                Region { item: tab }
            }

            HoverHandler {
                id: edgeHover
            }

            Timer {
                running: edgeHover.hovered && !edge.peek && !root.open
                interval: 120
                onTriggered: edge.peek = true
            }

            Timer {
                running: !edgeHover.hovered && edge.peek
                interval: 450
                onTriggered: edge.peek = false
            }

            Item {
                id: strip
                anchors.right: parent.right
                width: 1
                height: parent.height
            }

            // Pokes out of the edge; its right end hides past the screen,
            // so only the left corners show rounded
            Rectangle {
                id: tab

                readonly property bool hot: tabArea.containsMouse
                property int visibleWidth: hot ? 46 : 40
                property real reveal: 0
                Component.onCompleted: reveal = edge.out ? 1 : 0

                // Started by hand, so the curve matches the direction (see Popouts)
                Connections {
                    target: edge
                    function onOutChanged() {
                        tabAnim.stop();
                        tabAnim.to = edge.out ? 1 : 0;
                        tabAnim.duration = edge.out ? Theme.animSpatial : 260 * Theme.speed;
                        tabAnim.easing.bezierCurve = edge.out ? Theme.spatial : Theme.emphasizedAccel;
                        tabAnim.start();
                    }
                }
                NumberAnimation {
                    id: tabAnim
                    target: tab
                    property: "reveal"
                    easing.type: Easing.BezierSpline
                }

                x: edge.width - visibleWidth * reveal
                anchors.verticalCenter: parent.verticalCenter
                width: visibleWidth + radius
                height: column.implicitHeight + 28
                radius: 16
                color: Qt.alpha(Theme.bg, 0.85)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, hot ? 0.45 : 0.25)
                opacity: reveal

                Behavior on visibleWidth { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
                Behavior on height { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: Theme.anim } }

                Column {
                    id: column

                    x: (tab.visibleWidth - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Notifs.dnd ? "do_not_disturb_on" : Notifs.list.length > 0 ? "notifications_unread" : "notifications"
                        font.pixelSize: 21
                        color: Notifs.list.length > 0 || Notifs.dnd ? Theme.accent : Theme.subtext
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Notifs.list.length > 0
                        width: Math.max(height, tabCount.implicitWidth + 10)
                        height: 20
                        radius: height / 2
                        color: Qt.alpha(Theme.accent, 0.18)

                        Label {
                            id: tabCount
                            anchors.centerIn: parent
                            text: Notifs.list.length > 99 ? "99+" : Notifs.list.length
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Theme.accent
                        }
                    }
                }

                MouseArea {
                    id: tabArea
                    onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        edge.peek = false;
                        root.show(edge.modelData);
                    }
                }
            }
        }
    }

    PanelWindow {
        id: win

        screen: root.screen
        // Stays mapped: remapping a layer surface on every open costs the first frames
        visible: true
        WlrLayershell.namespace: "notifcenter"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        anchors {
            top: true
            bottom: true
            right: true
        }
        // Spare room on the left, so a panel springing past its spot isn't cut by the window edge
        readonly property int room: 100
        implicitWidth: room + root.cardWidth + Theme.pad * 2 + root.gap
        color: "transparent"
        mask: Region { item: panel }

        HyprlandFocusGrab {
            windows: [win]
            active: root.open
            onCleared: root.hide()
        }

        Rectangle {
            id: panel

            readonly property real maxHeight: win.height - root.gap * 2
            // 0 shown, 1 tucked away past the screen edge
            // Slides only once the cards are built, so creation never stalls the animation
            property real shift: root.open && panelLoader.status === Loader.Ready ? 0 : 1

            // Springing past its spot (shift < 0) is damped: the panel is wide, so a full overshoot flies far
            x: win.room + (Theme.motionStyle === "slide" ? (shift < 0 ? shift * 0.35 : shift) * win.width : 0)
            y: root.gap
            opacity: Theme.revealOpacity(1 - shift)
            scale: Theme.revealScale(1 - shift)
            transformOrigin: Item.TopRight
            width: root.cardWidth + Theme.pad * 2
            height: Math.min(maxHeight, (panelLoader.item?.implicitHeight ?? 0) + Theme.pad * 2)
            radius: Theme.radius + 6
            color: Qt.alpha(Theme.bg, 0.85)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.25)
            clip: true
            visible: root.open || shift < 1

            Behavior on shift {
                NumberAnimation {
                    duration: root.open ? Theme.animPanel : 300 * Theme.speed
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.open ? Theme.emphasizedDecel : Theme.emphasizedAccel
                }
            }
            // A collapsing card already moves smoothly; easing on top would lag behind it
            Behavior on height {
                enabled: panel.shift === 0 && !Notifs.list.some(n => n.leaving)
                NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.hide()
                Keys.onDeletePressed: root.clearAll()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace) root.clearAll();
                }
            }

            // Rebuilt on every open, so the cards cascade in again
            Loader {
                id: panelLoader

                x: Theme.pad
                y: Theme.pad
                width: parent.width - Theme.pad * 2
                active: root.open || panel.shift < 1
                asynchronous: true

                sourceComponent: Column {
                    readonly property alias list: list

                    spacing: 14

                    Item {
                        width: parent.width
                        height: 32

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications"
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Notifs.list.length > 0
                                width: Math.max(height, countLabel.implicitWidth + 12)
                                height: 20
                                radius: height / 2
                                color: Qt.alpha(Theme.accent, 0.18)

                                Label {
                                    id: countLabel
                                    anchors.centerIn: parent
                                    text: Notifs.list.length
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Theme.accent
                                }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            HeaderButton {
                                icon: Notifs.dnd ? "do_not_disturb_on" : "notifications_active"
                                active: Notifs.dnd
                                onClicked: Notifs.setDnd(!Notifs.dnd)
                            }

                            HeaderButton {
                                icon: "clear_all"
                                enabled: Notifs.list.length > 0 && !sweep.running
                                opacity: enabled ? 1 : 0.35
                                onClicked: root.clearAll()
                            }
                        }
                    }

                    ListView {
                        id: list

                        width: parent.width
                        height: Math.min(Math.max(0, contentHeight - root.gap), panel.maxHeight - Theme.pad * 2 - 32 - parent.spacing)
                        visible: list.count > 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        model: ScriptModel {
                            values: Notifs.list
                        }

                        delegate: Toast {
                            history: true
                            gap: root.gap
                            onActivated: root.hide()
                        }

                        populate: Transition {
                            id: intro
                            SequentialAnimation {
                                PropertyAction { property: "opacity"; value: 0 }
                                PropertyAction { property: "x"; value: 56 }
                                PauseAnimation { duration: 90 + Math.min(intro.ViewTransition.index, 8) * 40 }
                                ParallelAnimation {
                                    NumberAnimation { property: "x"; to: 0; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
                                    NumberAnimation { property: "opacity"; to: 1; duration: 220 }
                                }
                            }
                        }

                        add: Transition {
                            NumberAnimation { property: "x"; from: root.cardWidth; to: 0; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
                        }

                        displaced: Transition {
                            NumberAnimation { property: "y"; duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
                            NumberAnimation { property: "x"; to: 0; duration: Theme.anim }
                            NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim }
                        }
                    }

                    Column {
                        width: parent.width
                        visible: list.count === 0
                        topPadding: 18
                        bottomPadding: 14
                        spacing: 8

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Notifs.dnd ? "do_not_disturb_on" : "notifications"
                            fill: 0
                            weight: 400
                            font.pixelSize: 40
                            color: Qt.alpha(Theme.subtext, 0.7)
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Notifs.dnd ? "Do not disturb is on" : "All caught up"
                            font.pixelSize: 14
                            color: Theme.subtext
                        }
                    }
                }
            }
        }
    }

    component HeaderButton: Rectangle {
        id: button

        property string icon
        property bool active: false
        signal clicked

        width: 32
        height: 32
        radius: height / 2
        color: active ? Qt.alpha(Theme.accent, area.containsMouse ? 0.28 : 0.18)
            : Qt.alpha(Theme.text, area.containsMouse && enabled ? 0.1 : 0)
        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        Icon {
            anchors.centerIn: parent
            text: button.icon
            font.pixelSize: 19
            color: button.active ? Theme.accent : Theme.subtext
        }

        MouseArea {
            id: area
            onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
            onPressedChanged: if (pressed) Sfx.play("click")
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.clicked()
        }
    }
}
