import QtQuick
import QtQuick.Particles
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

// Pointer effects over everything, click-through: a trail and a ring visualizer around the cursor
PanelWindow {
    id: root

    readonly property var monitor: Hyprland.monitorFor(screen)
    // Hyprland's pixels per overlay pixel: the panel scale (QT_SCALE_FACTOR)
    readonly property real ui: Number(Quickshell.env("QT_SCALE_FACTOR") || 1)
    readonly property real cx: (Cursor.x - (monitor?.x ?? 0)) / ui
    readonly property real cy: (Cursor.y - (monitor?.y ?? 0)) / ui
    readonly property real ax: (Cursor.px - (monitor?.x ?? 0)) / ui
    readonly property real ay: (Cursor.py - (monitor?.y ?? 0)) / ui
    readonly property bool here: cx >= 0 && cy >= 0 && cx < width && cy < height
    readonly property color tint: Theme.accent

    // Hyprland stacks layers by when they were mapped, so a panel opened later covers this one:
    // it gets remapped on top whenever another layer opens
    property bool remap: false
    visible: Cursor.tracking && !remap

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openlayer" && event.data !== "cursorfx" && root.visible)
                root.remap = true;
        }
    }
    Timer {
        running: root.remap
        interval: 30
        onTriggered: root.remap = false
    }
    WlrLayershell.namespace: "cursorfx"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: Region {}

    // Comet: where the pointer was over the last moments, as one smooth tapering ribbon that
    // fades toward its tail and shrinks back into the pointer once it stops
    Item {
        id: comet

        // How long a point stays (ms), how wide the head is
        readonly property real life: 170
        readonly property real thickness: 9
        property var points: []
        // Ribbon outline, then where the fade runs from and to
        property var outline: []
        property point tail: Qt.point(0, 0)
        property point head: Qt.point(0, 0)
        property real reach: 0
        // Clear of the pointer: the trail shows from about its edge on, so a see-through
        // pointer (Fluent's hover circle) doesn't have it underneath
        readonly property real gap: Cursor.size * (Cursor.base === "Rice-Fluent" ? 0.3 : 0.12) / root.ui
        readonly property real start: reach > 0 ? Math.min(0.5, gap / reach) : 0

        // Woken by pointer motion, asleep once the trail has drained, so a still pointer redraws nothing
        property bool alive: false

        anchors.fill: parent
        visible: Settings.cursorTrail === "comet"

        Connections {
            target: Cursor
            function onXChanged() { comet.alive = true; }
            function onYChanged() { comet.alive = true; }
        }

        FrameAnimation {
            running: comet.visible && root.visible && comet.alive
            onTriggered: {
                const now = Date.now();
                let p = root.here ? comet.points.filter(q => now - q.t < comet.life) : [];
                const last = p[0];
                // Where Hyprland says, not ahead of it: prediction wobbles the line
                if (root.here && (!last || Math.hypot(last.x - root.cx, last.y - root.cy) > 0.5))
                    p.unshift({ x: root.cx, y: root.cy, t: now });
                if (p.length < 2 && comet.points.length < 2) {
                    comet.points = p;
                    if (comet.outline.length)
                        comet.outline = [];
                    comet.alive = p.length > 0;
                    return;
                }
                comet.points = p;
                comet.outline = comet.ribbon(p, now);
            }
        }

        // Catmull-Rom through the points, then offset both ways by a width that tapers to the tail
        function ribbon(raw, now) {
            if (raw.length < 2)
                return [];
            // Each point pulled toward its neighbours, twice, so a shaky hand still draws an arc
            let p = raw;
            for (let pass = 0; pass < 2; pass++)
                p = p.map((q, i) => i === 0 || i === p.length - 1 ? q : {
                    x: (p[i - 1].x + 2 * q.x + p[i + 1].x) / 4,
                    y: (p[i - 1].y + 2 * q.y + p[i + 1].y) / 4,
                    t: q.t
                });
            const s = [];
            for (let i = 0; i < p.length - 1; i++) {
                const p0 = p[Math.max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[Math.min(p.length - 1, i + 2)];
                const steps = Math.max(1, Math.min(8, Math.ceil(Math.hypot(p2.x - p1.x, p2.y - p1.y) / 6)));
                for (let k = 0; k < steps; k++) {
                    const t = k / steps, t2 = t * t, t3 = t2 * t;
                    const f = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
                    s.push({ x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y), t: p1.t + (p2.t - p1.t) * t });
                }
            }
            s.push(p[p.length - 1]);
            const left = [], right = [];
            for (let i = 0; i < s.length; i++) {
                const a = s[Math.max(0, i - 1)], b = s[Math.min(s.length - 1, i + 1)];
                const dx = b.x - a.x, dy = b.y - a.y, d = Math.hypot(dx, dy) || 1;
                const age = Math.min(1, (now - s[i].t) / life);
                const w = thickness / 2 * Math.pow(1 - age, 0.8) * Math.min(1, i / 3 + 0.4);
                left.push(Qt.point(s[i].x - dy / d * w, s[i].y + dx / d * w));
                right.push(Qt.point(s[i].x + dy / d * w, s[i].y - dx / d * w));
            }
            head = Qt.point(s[0].x, s[0].y);
            tail = Qt.point(s[s.length - 1].x, s[s.length - 1].y);
            reach = Math.hypot(tail.x - head.x, tail.y - head.y);
            return left.concat(right.reverse(), [left[0]]);
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: comet.outline.length > 0

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: comet.head.x
                    y1: comet.head.y
                    x2: comet.tail.x
                    y2: comet.tail.y
                    GradientStop { position: 0; color: Qt.alpha(root.tint, 0) }
                    GradientStop { position: comet.start; color: Qt.alpha(root.tint, 0) }
                    GradientStop { position: Math.min(0.55, comet.start * 1.6 + 0.02); color: Qt.alpha(root.tint, 0.9) }
                    GradientStop { position: 0.75; color: Qt.alpha(root.tint, 0.35) }
                    GradientStop { position: 1; color: Qt.alpha(root.tint, 0) }
                }
                PathPolyline {
                    path: comet.outline
                }
            }
        }
    }

    // Sparks: glowing bits shed while the pointer moves
    ParticleSystem {
        id: sparks

        anchors.fill: parent
        running: Settings.cursorTrail === "sparks" && root.visible

        ImageParticle {
            source: "qrc:///particleresources/glowdot.png"
            color: root.tint
            colorVariation: 0.08
            alpha: 0
            entryEffect: ImageParticle.Scale
        }

        Emitter {
            id: emitter

            property real lastX: 0
            property real lastY: 0
            property real speed: 0

            x: root.cx
            y: root.cy
            enabled: root.here && speed > 0.5
            emitRate: Math.min(400, 40 + speed * 12)
            lifeSpan: 700
            lifeSpanVariation: 300
            size: 14
            endSize: 2
            sizeVariation: 6
            velocity: AngleDirection {
                angleVariation: 360
                magnitude: 30
                magnitudeVariation: 25
            }
            acceleration: PointDirection {
                y: 40
            }

            FrameAnimation {
                running: sparks.running
                onTriggered: {
                    const d = Math.hypot(root.cx - emitter.lastX, root.cy - emitter.lastY);
                    emitter.speed = emitter.speed * 0.6 + d * 0.4;
                    emitter.lastX = root.cx;
                    emitter.lastY = root.cy;
                }
            }
        }
    }

    // Spectrum all the way around the pointer, lows at the top going clockwise
    Item {
        id: ring

        readonly property int n: Settings.vizBars
        readonly property real inner: Settings.vizRadius
        readonly property real reach: Settings.vizHeight
        // Cava's bars stretched or squeezed to n, wrapping around
        readonly property var values: {
            if (!visible)
                return [];
            const src = Cava.values, m = src.length, out = [];
            for (let i = 0; i < n; i++) {
                const p = i * m / n, j = Math.floor(p), f = p - j;
                out.push((src[j] ?? 0) * (1 - f) + (src[(j + 1) % m] ?? 0) * f);
            }
            return out;
        }
        // Points of the line styles: Catmull-Rom through each bar's tip, closed
        readonly property var outline: {
            if (Settings.vizStyle !== "wave" && Settings.vizStyle !== "blob")
                return [];
            const r = values.map(v => inner + 2 + v * reach);
            const pts = [], k = 4;
            for (let i = 0; i < n; i++) {
                const p0 = r[(i - 1 + n) % n], p1 = r[i], p2 = r[(i + 1) % n], p3 = r[(i + 2) % n];
                for (let s = 0; s < k; s++) {
                    const t = s / k;
                    const rr = 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);
                    const a = (i + t) / n * 2 * Math.PI - Math.PI / 2;
                    pts.push(Qt.point(Math.cos(a) * rr, Math.sin(a) * rr));
                }
            }
            pts.push(pts[0]);
            return pts;
        }

        x: root.ax
        y: root.ay
        visible: Settings.cursorViz && root.here && opacity > 0
        opacity: Cava.active && !Cursor.idle ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        RotationAnimation on rotation {
            running: Settings.vizSpin && ring.visible
            from: 0
            to: 360
            duration: 12000
            loops: Animation.Infinite
        }

        Repeater {
            model: Settings.cursorViz && (Settings.vizStyle === "bars" || Settings.vizStyle === "dots") ? ring.n : 0

            Item {
                required property int index
                readonly property real v: ring.values[index] ?? 0
                readonly property bool dots: Settings.vizStyle === "dots"

                rotation: index * 360 / ring.n

                Rectangle {
                    readonly property real w: Math.max(1.5, Math.min(4, 2 * Math.PI * ring.inner / ring.n * 0.55))

                    width: parent.dots ? w + 1.5 + parent.v * 3 : w
                    height: parent.dots ? width : 3 + parent.v * ring.reach
                    radius: width / 2
                    x: -width / 2
                    y: parent.dots ? -ring.inner - parent.v * ring.reach - height / 2 : -ring.inner - height
                    color: root.tint
                    opacity: 0.55 + 0.45 * parent.v
                    antialiasing: true
                }
            }
        }

        Shape {
            visible: ring.outline.length > 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.tint
                strokeWidth: 2
                fillColor: Settings.vizStyle === "blob" ? Qt.alpha(root.tint, 0.35) : "transparent"
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: ring.outline
                }
            }
        }
    }
}
