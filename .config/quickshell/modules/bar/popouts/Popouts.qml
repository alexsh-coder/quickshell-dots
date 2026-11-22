import QtQuick
import QtQuick.Shapes
import qs.config

// One panel that slides out from behind the bar and morphs between pages:
// it glides to the hovered item, resizes to the page and cross-fades content
Item {
    id: root

    property string current: ""
    // Keeps the panel open while the pointer is away, e.g. typing a password
    property bool pinned: false
    // A slider is held, so leaving the panel must not close it mid-drag
    property bool busy: false
    readonly property bool open: current !== ""
    readonly property Item hitbox: panel
    readonly property int flare: 14
    readonly property int corner: Theme.radius + 6
    readonly property int overlap: 6

    property string shownName: ""
    // Page, place and size jump instead of animating
    property bool instant: false
    // Media page shows its music effects section
    property bool fx: false
    property real center: 0
    property real drawnCenter: center
    readonly property Item page: ({ keyboard: keyboardPage, network: networkPage, vpn: vpnPage, bluetooth: bluetoothPage, volume: volumePage, power: powerPage, calendar: calendarPage, battery: batteryPage, media: mediaPage })[shownName] ?? null

    function show(name, item) {
        closeTimer.stop();
        if (pinned && name !== current)
            return;
        // Opening anew (or over a closing panel) starts on the new page, with no fade from the old one
        instant = !open;
        center = item.mapToItem(root, item.width / 2, 0).x;
        shownName = name;
        current = name;
        instant = false;
    }

    function leave() {
        if (open && !pinned && !busy && !closeTimer.running)
            closeTimer.start();
    }

    function stay() {
        closeTimer.stop();
    }

    function close() {
        closeTimer.stop();
        pinned = false;
        current = "";
    }

    onCurrentChanged: if (current !== "media") fx = false

    Timer {
        id: closeTimer
        interval: root.current === "media" ? 700 : 280
        onTriggered: root.current = ""
    }

    Behavior on drawnCenter {
        enabled: root.reveal > 0 && !root.instant
        NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
    }

    // 0 = tucked behind the bar, 1 = fully out. The panel keeps its real height,
    // so its corners stay round the whole way
    property real reveal: 0

    // Started by hand: a Behavior would start before its easing binding sees the new open,
    // running the opening with the closing curve and back
    onOpenChanged: {
        revealAnim.stop();
        revealAnim.to = open ? 1 : 0;
        // Taller panels travel further, so they take longer, just not in proportion
        revealAnim.duration = (open ? 240 + 0.45 * panel.height : 230 + 0.4 * panel.height) * Theme.speed;
        revealAnim.easing.bezierCurve = open ? Theme.emphasizedDecel : Theme.emphasizedAccel;
        revealAnim.start();
    }

    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        easing.type: Easing.BezierSpline
    }

    // Everything drawn; the in-place styles fade and scale it from under the hovered item
    Item {
        id: stage

        anchors.fill: parent
        visible: root.reveal > 0
        opacity: Theme.revealOpacity(root.reveal)
        transform: Scale {
            origin.x: panel.x + panel.width / 2
            origin.y: Theme.barHeight
            xScale: Theme.revealScale(root.reveal)
            yScale: xScale
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Panel body at its real position; the part still behind the bar is covered by it
            ShapePath {
                fillColor: Theme.bg
                strokeWidth: -1

                PathRectangle {
                    x: panel.x
                    // Reaches up under the bar: with fractional scaling two half-covered
                    // edges meeting on one pixel row would leave a seam
                    // Overshooting past fully out must not open a gap under the bar
                    y: Math.min(panel.y, Theme.barHeight) - root.overlap
                    width: panel.width
                    height: panel.y + panel.height - y
                    bottomLeftRadius: root.corner
                    bottomRightRadius: root.corner
                }
            }

            // Concave flares where the panel meets the bar edge. They only grow along
            // the straight part of the side that is already out, so they never kink
            ShapePath {
                id: flares

                readonly property real top: Theme.barHeight
                readonly property real x0: panel.x
                readonly property real x1: panel.x + panel.width
                readonly property real r: Math.max(0, Math.min(root.flare, panel.y + panel.height - root.corner - top))

                fillColor: Theme.bg
                strokeWidth: -1

                startX: flares.x0 - flares.r
                startY: flares.top - root.overlap
                PathLine { x: flares.x0 - flares.r; y: flares.top }
                PathArc { x: flares.x0; y: flares.top + flares.r; radiusX: flares.r; radiusY: flares.r; direction: PathArc.Clockwise }
                PathLine { x: flares.x0; y: flares.top - root.overlap }
                PathMove { x: flares.x1; y: flares.top - root.overlap }
                PathLine { x: flares.x1; y: flares.top + flares.r }
                PathArc { x: flares.x1 + flares.r; y: flares.top; radiusX: flares.r; radiusY: flares.r; direction: PathArc.Clockwise }
                PathLine { x: flares.x1 + flares.r; y: flares.top - root.overlap }
            }
        }

        Item {
            id: panel

            y: Theme.barHeight - (1 - (Theme.motionStyle === "slide" ? root.reveal : 1)) * height
            width: root.page?.implicitWidth ?? 0
            height: root.page?.implicitHeight ?? 0
            x: Math.round(Math.max(root.flare + 6, Math.min(root.width - width - root.flare - 6, root.drawnCenter - width / 2)))
            clip: true

            // A click inside a hover-opened panel pins it, which hands it the keyboard.
            // Passive, so the controls under the pointer still get the press
            PointHandler {
                acceptedButtons: Qt.AllButtons
                onActiveChanged: if (active && root.open) root.pinned = true
            }

            Behavior on width {
                enabled: root.reveal > 0 && !root.instant
                NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
            }
            Behavior on height {
                enabled: root.reveal > 0 && !root.instant
                NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
            }

            Item {
                id: pages
                anchors.fill: parent

                Page { id: keyboardPage; name: "keyboard"; KeyboardPopout { popouts: root; here: parent.here } }
                Page { id: networkPage; name: "network"; NetworkPopout { popouts: root; here: parent.here } }
                Page { id: vpnPage; name: "vpn"; VpnPopout { popouts: root; here: parent.here } }
                Page { id: bluetoothPage; name: "bluetooth"; BluetoothPopout { popouts: root; here: parent.here } }
                Page { id: volumePage; name: "volume"; VolumePopout { popouts: root; here: parent.here } }
                Page { id: batteryPage; name: "battery"; BatteryPopout { popouts: root; here: parent.here } }
                Page { id: calendarPage; name: "calendar"; CalendarPopout { popouts: root; here: parent.here } }
                Page { id: powerPage; name: "power"; PowerPopout { popouts: root; here: parent.here } }
                Page { id: mediaPage; name: "media"; MediaPopout { popouts: root; here: parent.here } }
            }
        }

    }

    component Page: Item {
        required property string name
        readonly property bool here: root.open && root.shownName === name

        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        width: implicitWidth
        height: implicitHeight
        // Pinned to the top, so it rides along with the panel
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: root.shownName === name ? 1 : 0
        visible: opacity > 0
        enabled: here

        transform: Translate {
            y: here ? 0 : -12
            Behavior on y { enabled: !root.instant; NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
        }
        Behavior on opacity { enabled: !root.instant; NumberAnimation { duration: 300 * Theme.speed; easing.type: Easing.OutCubic } }
    }
}
