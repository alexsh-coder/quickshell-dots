import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services

// One window on the ring. Drawn at the window's real size; the projective matrix from
// Overview places it either exactly over the real window or on the ring.
Item {
    id: card

    required property var modelData
    required property int index
    required property var overview

    readonly property var entry: modelData
    readonly property real slot: overview.slot(index)
    readonly property var pose: overview.pose(entry, slot, flat, overview.progress)
    readonly property bool selected: overview.selectedIndex === index
    readonly property bool shown: pose.op > 0.002
    readonly property bool flat: overview.flatSet.includes(entry.address)
    // Near its real place the card shows the real screen, compositor blur and all
    readonly property real realMix: flat && overview.captureValid && overview.screenFrame?.hasContent
        ? Math.max(0, 1 - overview.progress / 0.3) : 0

    width: entry.w
    height: entry.h
    visible: shown
    opacity: pose.op
    z: -pose.d

    transform: Matrix4x4 {
        matrix: card.overview.matrix(card.pose, card.width, card.height)
    }

    // Hyprland draws the border outside the window and rounds the content to 10
    ClippingRectangle {
        id: frame

        x: -2
        y: -2
        width: parent.width + 4
        height: parent.height + 4
        radius: 12
        color: "transparent"
        border.width: 2
        border.color: card.selected ? Qt.alpha(Theme.accent, 0.93) : "#aa595959"
        antialiasing: true

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: card.overview.softWall
            sourceRect: Qt.rect(card.entry.x + card.overview.originX, card.entry.y + card.overview.originY, card.entry.w, card.entry.h)
        }

        IconImage {
            anchors.centerIn: parent
            visible: !shot.hasContent
            implicitSize: Math.min(parent.width, parent.height) * 0.25
            source: Quickshell.iconPath(DesktopEntries.heuristicLookup(card.entry.appClass)?.icon ?? card.entry.appClass, "application-x-executable")
        }

        ScreencopyView {
            id: shot

            anchors.fill: parent
            captureSource: card.entry.toplevel
            live: card.shown
            paintCursor: false
        }

        ShaderEffectSource {
            anchors.fill: parent
            visible: card.realMix > 0
            opacity: card.realMix
            sourceItem: card.overview.screenFrame
            sourceRect: Qt.rect(card.entry.x + card.overview.originX, card.entry.y + card.overview.originY, card.entry.w, card.entry.h)
        }

        // Side windows sink into the dark
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.5 * Math.min(1, Math.abs(card.slot)) * card.overview.progress
        }
    }

    // Floor reflection: the frame's lower part, masked to fade towards the far edge, then flipped
    Item {
        id: reflection

        y: card.height + 2 + 10
        x: -2
        width: frame.width
        height: frame.height * 0.4
        visible: card.overview.progress > 0.01
        opacity: 0.22 * card.overview.progress

        ShaderEffectSource {
            id: mirror

            anchors.fill: parent
            sourceItem: frame
            sourceRect: Qt.rect(0, frame.height * 0.6, frame.width, frame.height * 0.4)
            visible: false
        }

        Rectangle {
            id: fade

            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: "white" }
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: mirror
            maskEnabled: true
            maskSource: fade
            maskThresholdMin: 0
            maskSpreadAtMin: 1
            transform: Scale { yScale: -1; origin.y: reflection.height / 2 }
        }
    }

    MouseArea {
        onReleased: if (containsMouse) Sfx.tap("click")
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.BlankCursor
        onClicked: card.overview.pick(card.index)
    }
}
