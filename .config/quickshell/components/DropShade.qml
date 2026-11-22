import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

// Full-screen shade on the focused monitor: drops from the top in free fall,
// bounces off the bottom edge and rises back without a bounce. With followMotion
// it comes the way the shell motion preset says instead (Theme.motions).
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
    property bool followMotion: false
    // "fall" (free fall with bounces), "slide" (eased drop) or one of the in-place styles
    readonly property string style: !followMotion ? "fall"
        : Theme.motionStyle !== "slide" ? Theme.motionStyle
        : Settings.motion === "m3" || Settings.motion === "bouncy" ? "fall" : "slide"
    readonly property bool inPlace: style !== "fall" && style !== "slide"

    function show() {
        landed = false;
        stopAll();
        open = true;
        shade.vy = 0;
        if (style === "fall") {
            shade.reveal = 1;
            shade.y = -shade.height;
            fall.running = true;
        } else if (style === "slide") {
            shade.reveal = 1;
            shade.y = -shade.height;
            run(slideAnim, "y", 0, Theme.animPanel * 1.2, Theme.emphasizedDecel);
        } else {
            shade.y = 0;
            shade.reveal = 0;
            landed = true;
            run(revealAnim, "reveal", 1, Theme.animPanel, style === "fade" ? Theme.emphasizedDecel : Theme.spatial);
        }
    }

    function hide() {
        // Leave first: the window stays up only while open or leaving
        stopAll();
        if (inPlace)
            run(revealAnim, "reveal", 0, 300 * Theme.speed, Theme.emphasizedAccel);
        else
            run(slideAnim, "y", -shade.height, 420 * (followMotion ? Theme.speed : 1), Theme.emphasizedAccel);
        open = false;
    }

    function stopAll() {
        fall.running = false;
        slideAnim.stop();
        revealAnim.stop();
    }

    function run(anim, prop, to, duration, curve) {
        anim.property = prop;
        anim.to = to;
        anim.duration = duration;
        anim.easing.bezierCurve = curve;
        anim.start();
    }

    function toggle() {
        if (open)
            hide();
        else
            show();
    }

    visible: open || slideAnim.running || revealAnim.running
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
        // In-place styles: 0 gone, 1 shown
        property real reveal: 1
        opacity: win.inPlace ? Math.max(0, Math.min(1, reveal * 1.4)) : 1
        scale: !win.inPlace ? 1 : win.style === "pop" ? 0.85 + 0.15 * reveal : win.style === "zoom" ? 1.06 - 0.06 * Math.min(1, reveal) : 1

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
            id: slideAnim
            target: shade
            easing.type: Easing.BezierSpline
            // An eased drop lands once it's in place
            onFinished: if (win.open) win.landed = true
        }
        NumberAnimation {
            id: revealAnim
            target: shade
            easing.type: Easing.BezierSpline
        }

        MouseArea {
            anchors.fill: parent
            onClicked: win.hide()
        }
    }
}
