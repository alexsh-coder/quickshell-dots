import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    readonly property var entry: modelData
    // Shown in the notification center: no countdown, acting on it dismisses it
    property bool history: false

    signal activated

    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property int timeout: critical ? 0
        : entry.timeout > 0 ? Math.max(entry.timeout, 2000)
        : entry.urgency === NotificationUrgency.Low ? 3500 : 6000
    readonly property color tint: critical ? Theme.urgent : Theme.accent
    readonly property var defaultAction: entry.actions.find(a => a.id === "default") ?? null
    readonly property var buttons: entry.actions.filter(a => a.id !== "default" && a.text)
    readonly property bool held: hover.hovered || area.drag.active

    // notify-send -i and many apps pass an icon name as the image
    readonly property bool imageIsIcon: /^image:\/\/icon\/[^\/]/.test(entry.image)
    readonly property string picture: imageIsIcon ? "" : entry.image
    readonly property string appIconSource: {
        if (imageIsIcon)
            return entry.image;
        const icon = entry.appIcon
            || DesktopEntries.byId(entry.desktopEntry)?.icon
            || DesktopEntries.heuristicLookup(entry.appName)?.icon
            || "";
        if (!icon)
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.includes("://"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }

    // Space below the card, kept inside it so a closing card takes it along
    property int gap: 0
    property real collapse: 1

    width: ListView.view.width
    height: (card.height + gap) * collapse
    clip: collapse < 1

    // History cards leave on their own: slide out, then close the gap
    SequentialAnimation {
        running: root.history && root.entry.leaving
        NumberAnimation { target: card; property: "x"; to: card.width; duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedAccel }
        NumberAnimation { target: root; property: "collapse"; to: 0; duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
    }

    property real life: 1

    NumberAnimation {
        id: countdown
        target: root
        property: "life"
        from: 1
        to: 0
        duration: root.timeout
        running: !root.history && root.timeout > 0
        paused: running && root.held
        onFinished: root.entry.popup = false
    }

    Connections {
        target: root.entry
        function onRefreshed() {
            if (!root.history && root.timeout > 0)
                countdown.restart();
        }
    }

    function act(id) {
        if (id)
            entry.invoke(id);
        if (history) {
            if (id)
                entry.close();
            activated();
        } else {
            entry.popup = false;
        }
    }

    function activate() {
        if (defaultAction || !history)
            act(defaultAction?.id ?? "");
    }

    Rectangle {
        id: card

        width: parent.width
        height: content.implicitHeight + 28
        radius: Theme.radius + 4
        color: root.history ? Theme.surface : Qt.alpha(Theme.bg, 0.88)
        border.width: 1
        border.color: root.critical ? Qt.alpha(Theme.urgent, 0.6) : Qt.alpha(Theme.text, root.held ? 0.1 : 0.05)
        opacity: 1 - Math.max(0, x) / width * 0.8

        Behavior on border.color { ColorAnimation { duration: Theme.anim } }

        HoverHandler {
            id: hover
        }

        MouseArea {
            id: area
            onPressedChanged: if (pressed) Sfx.play("click")

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: root.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
            drag.target: card
            drag.axis: Drag.XAxis
            drag.minimumX: 0
            drag.maximumX: card.width

            onClicked: mouse => mouse.button === Qt.LeftButton ? root.activate() : root.entry.close()
            onReleased: {
                if (card.x > card.width * 0.3)
                    flyOut.start();
                else if (card.x > 0)
                    snapBack.start();
            }
        }

        NumberAnimation {
            id: snapBack
            target: card
            property: "x"
            to: 0
            duration: Theme.animSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.spatial
        }

        SequentialAnimation {
            id: flyOut
            NumberAnimation { target: card; property: "x"; to: card.width; duration: 200; easing.type: Easing.OutCubic }
            ScriptAction { script: root.entry.close() }
        }

        Row {
            id: content

            x: 14
            y: 14
            width: parent.width - 28
            spacing: 12

            Item {
                id: art
                width: 44
                height: 44

                ClippingRectangle {
                    visible: pic.status === Image.Ready
                    anchors.fill: parent
                    radius: 10
                    color: Theme.surface

                    Image {
                        id: pic
                        anchors.fill: parent
                        source: root.picture
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(88, 88)
                        cache: false
                    }
                }

                // App icon as a badge over the picture, or on its own
                IconImage {
                    id: appIcon
                    readonly property bool badge: pic.status === Image.Ready
                    visible: status === Image.Ready
                    implicitSize: badge ? 18 : 36
                    anchors.centerIn: badge ? undefined : parent
                    anchors.right: badge ? parent.right : undefined
                    anchors.bottom: badge ? parent.bottom : undefined
                    anchors.margins: -3
                    source: root.appIconSource
                }

                Rectangle {
                    visible: pic.status !== Image.Ready && !appIcon.visible
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.alpha(root.tint, 0.15)

                    Icon {
                        anchors.centerIn: parent
                        text: root.critical ? "priority_high" : "notifications"
                        font.pixelSize: 22
                        color: root.tint
                    }
                }
            }

            Column {
                width: parent.width - art.width - parent.spacing
                spacing: 4

                Item {
                    width: parent.width
                    height: 18

                    Label {
                        anchors.left: parent.left
                        anchors.right: closeButton.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: [root.entry.appName, Qt.formatTime(root.entry.time, "hh:mm")].filter(s => s).join(" · ")
                        font.pixelSize: 12
                        color: Theme.subtext
                    }

                    Rectangle {
                        id: closeButton

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        radius: height / 2
                        color: Qt.alpha(Theme.text, closeArea.containsMouse ? 0.12 : 0)
                        opacity: root.held ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                        Behavior on color { ColorAnimation { duration: Theme.anim } }

                        Icon {
                            anchors.centerIn: parent
                            text: "close"
                            font.pixelSize: 16
                            color: Theme.subtext
                        }

                        MouseArea {
                            id: closeArea
                            onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                            onPressedChanged: if (pressed) Sfx.play("click")
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.entry.close()
                        }
                    }
                }

                Label {
                    width: parent.width
                    visible: text !== ""
                    text: root.entry.summary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    // Images in the body aren't supported
                    text: root.entry.body.replace(/<img[^>]*>/gi, "").trim()
                    textFormat: Text.StyledText
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.subtext
                    linkColor: root.tint
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    lineHeight: 1.1
                    onLinkActivated: link => Qt.openUrlExternally(link)

                    HoverHandler {
                        enabled: parent.hoveredLink !== ""
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Flow {
                    width: parent.width
                    visible: root.buttons.length > 0
                    topPadding: 6
                    spacing: 6

                    Repeater {
                        model: root.buttons

                        Rectangle {
                            id: button

                            required property var modelData

                            width: Math.min(buttonLabel.implicitWidth + 24, parent.width)
                            height: 28
                            radius: height / 2
                            color: Qt.alpha(Theme.secondary, buttonArea.pressed ? 0.28 : buttonArea.containsMouse ? 0.2 : 0.12)

                            Behavior on color { ColorAnimation { duration: Theme.anim } }

                            Label {
                                id: buttonLabel
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - 24)
                                elide: Text.ElideRight
                                text: button.modelData.text
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: buttonArea
                                onContainsMouseChanged: if (containsMouse) Sfx.play("hover")
                                onPressedChanged: if (pressed) Sfx.play("click")
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.act(button.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // Time left; stops while the card is hovered
        // Bottom strip of a card-shaped fill, so the ends follow the corners
        Item {
            visible: !root.history && root.timeout > 0
            x: 1
            y: card.height - 3
            width: (card.width - 2) * root.life
            height: 2
            clip: true

            Rectangle {
                y: -(card.height - 4)
                width: card.width - 2
                height: card.height - 2
                radius: card.radius - 1
                color: Qt.alpha(root.tint, 0.7)
            }
        }
    }
}
