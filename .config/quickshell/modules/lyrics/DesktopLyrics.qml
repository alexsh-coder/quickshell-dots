import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Synced lyrics on the desktop layer: under windows, click-through
PanelWindow {
    id: root

    readonly property bool active: MusicFx.lyrics && Lyrics.lines.length > 0
    readonly property int moveDuration: 600
    readonly property int growDuration: 450

    visible: active || view.opacity > 0

    WlrLayershell.namespace: "lyrics"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    margins.bottom: Math.round(screen.height * 0.14)
    implicitWidth: Math.round(screen.width * 0.5)
    implicitHeight: 150
    color: "transparent"
    mask: Region {}

    ListView {
        id: view

        anchors.fill: parent
        model: root.active ? Lyrics.lines : []
        currentIndex: Lyrics.index
        interactive: false
        spacing: 4

        // Scroll by animating a hidden highlight, so the list glides on a custom
        // curve instead of ListView's built-in SmoothedAnimation
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (height - 32) / 2
        preferredHighlightEnd: (height + 32) / 2
        highlightFollowsCurrentItem: false
        highlight: Item {
            width: view.width
            height: view.currentItem?.height ?? 0
            y: view.currentItem?.y ?? 0
            Behavior on y {
                NumberAnimation {
                    duration: root.moveDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emphasizedDecel
                }
            }
        }

        opacity: root.active ? (Lyrics.player?.isPlaying ? 1 : 0.45) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            // Dense halo instead of a drop shadow, so light text holds up on light wallpapers
            shadowOpacity: 0.85
            shadowBlur: 0.45
        }

        delegate: Text {
            required property var modelData
            required property int index

            readonly property int dist: Math.abs(index - view.currentIndex)

            width: view.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: modelData.text || "♪"
            font.family: Theme.font
            font.pixelSize: 22
            font.weight: Font.Bold
            color: dist === 0 ? Theme.accent : Theme.text
            // Subtitle-style crisp edge under the halo
            style: Text.Outline
            styleColor: Qt.alpha("#000000", 0.7)
            opacity: dist === 0 ? 1 : dist === 1 ? 0.6 : 0
            scale: dist === 0 ? 1 : 0.75

            Behavior on scale {
                NumberAnimation {
                    duration: root.growDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emphasizedDecel
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: root.growDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emphasizedDecel
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: root.growDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emphasizedDecel
                }
            }
        }
    }

    IpcHandler {
        target: "lyrics"

        function toggle(): void {
            MusicFx.lyrics = !MusicFx.lyrics;
        }
    }
}
