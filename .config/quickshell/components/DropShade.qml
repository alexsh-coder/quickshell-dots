import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config

// Full-screen shade on the focused monitor: drops from the top in free fall,
// bounces off the bottom edge and rises back without a bounce.
// Children go onto the shade; a click on the shade itself closes it
PanelWindow {
    id: win

    property bool open: false
    // Set on the first impact, so content can pop in as the shade lands
    property bool landed: false
    property string namespace: "shade"
    property color shadeColor: Qt.alpha(Theme.bg, 0.88)
    default property alias content: shade.data
    readonly property Item shade: shade

    function show() {
        landed = false;
        rise.stop();
        open = true;
        shade.y = -shade.height;
        shade.vy = 0;
        fall.running = true;
    }

    function hide() {
        // Rise first: the window stays up only while open or rising
        fall.running = false;
        rise.restart();
        open = false;
    }

    function toggle() {
        if (open)
            hide();
        else
            show();
    }

    visible: open || rise.running
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    WlrLayershell.namespace: namespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    Rectangle {
        id: shade

        width: parent.width
        // From the screen, not the window: a freshly mapped window is still 0 high
        height: win.screen?.height ?? 1080
        y: -height
        color: win.shadeColor
        clip: true

        // Free fall in px/s, bouncing off the bottom edge with some energy lost each hit
        property real vy: 0
        readonly property real gravity: height * 14.4
        readonly property real restitution: 0.38

        FrameAnimation {
            id: fall

            onTriggered: {
                const dt = Math.min(frameTime, 1 / 30);
                shade.vy += shade.gravity * dt;
                shade.y += shade.vy * dt;
                if (shade.y < 0)
                    return;
                shade.y = 0;
                win.landed = true;
                if (shade.vy < shade.height * 0.3) {
                    shade.vy = 0;
                    running = false;
                } else {
                    shade.vy = -shade.vy * shade.restitution;
                }
            }
        }

        NumberAnimation {
            id: rise

            target: shade
            property: "y"
            to: -shade.height
            duration: 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedAccel
        }

        MouseArea {
            anchors.fill: parent
            onClicked: win.hide()
        }
    }
}
