import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services

// Full-screen spectrum on the desktop layer: under windows, click-through
PanelWindow {
    id: root

    readonly property bool active: MusicFx.desktop && Cava.active
    readonly property real gain: MusicFx.gain("desktop")
    readonly property list<real> values: Cava.values.map(v => Math.min(1, v * gain))
    readonly property int n: Cava.bars
    readonly property real w: width
    readonly property real h: height
    // Gaussian over neighbouring bars, so curves roll instead of spiking
    readonly property list<real> kernel: [0.05, 0.12, 0.2, 0.26, 0.2, 0.12, 0.05]

    // Spatial blur of the spectrum, eased against the previous frame
    function smoothed(prev, ease) {
        const half = (kernel.length - 1) / 2;
        const out = [];
        for (let i = 0; i < n; i++) {
            let s = 0;
            for (let k = 0; k < kernel.length; k++) {
                // Reflect at the ends, the curves continue into their mirrored half
                let j = Math.abs(i + k - half);
                if (j >= n)
                    j = 2 * n - 2 - j;
                s += (values[j] ?? 0) * kernel[k];
            }
            out.push((prev[i] ?? 0) * ease + s * (1 - ease));
        }
        return out;
    }

    // Catmull-Rom through the levels at fractional index m
    function spline(levels, m) {
        const i = Math.floor(m), f = m - i;
        const last = levels.length - 1;
        if (last < 0)
            return 0;
        // Reflect below 0 and clamp past the end; no closures, this runs thousands of times a frame
        const p0 = levels[Math.abs(Math.min(i - 1, last))], p1 = levels[Math.min(i, last)];
        const p2 = levels[Math.min(i + 1, last)], p3 = levels[Math.min(i + 2, last)];
        const v = 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (3 * p1 - p0 - 3 * p2 + p3) * f * f * f);
        return Math.max(0, Math.min(1, v));
    }

    visible: active || stage.opacity > 0

    WlrLayershell.namespace: "visualizer"
    WlrLayershell.layer: WlrLayer.Bottom
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

    Item {
        id: stage

        anchors.fill: parent
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

        layer.enabled: MusicFx.glow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.accent
            shadowBlur: 1
            shadowOpacity: Math.min(1, (0.35 + Cava.bass * 0.65) * MusicFx.gain("glow"))
            shadowScale: 1.02
        }

        // Extra layers first so they sit behind the main style
        Repeater {
            model: root.visible ? MusicFx.layers.filter(l => l !== MusicFx.style).concat([MusicFx.style]) : []

            Loader {
                required property string modelData

                anchors.fill: parent
                sourceComponent: ({ bars: bars, wave: wave, mirror: mirror, ring: ring, nation: nation, flow: flow })[modelData] ?? null
            }
        }
    }

    // Spectrum along the bottom edge
    Component {
        id: bars

        Row {
            readonly property real barW: (root.w - spacing * (root.n + 1)) / root.n

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            x: spacing
            spacing: 6

            Repeater {
                model: root.n

                Rectangle {
                    required property int index

                    anchors.bottom: parent.bottom
                    width: parent.barW
                    height: Math.max(4, root.values[index] * root.h * 0.16)
                    radius: Math.min(width / 2, 6)
                    color: Qt.alpha(Theme.accent, 0.35 + root.values[index] * 0.5)
                    Behavior on height { NumberAnimation { duration: 50 } }
                }
            }
        }
    }

    // Smooth filled curve rising from the bottom, mirrored so bass sits in the middle
    Component {
        id: wave

        Shape {
            id: shape

            readonly property int res: 160
            readonly property real peak: root.h * 0.2
            property var levels: []
            property var points: []

            // Mirrored around the center, bass in the middle
            function sample(t) {
                return root.spline(levels, Math.abs(t * 2 - 1) * (root.n - 1));
            }

            function rebuild() {
                levels = root.smoothed(levels, 0.55);
                const pts = [Qt.point(0, root.h)];
                for (let i = 0; i <= res; i++) {
                    const t = i / res;
                    pts.push(Qt.point(t * root.w, root.h - 4 - sample(t) * peak));
                }
                pts.push(Qt.point(root.w, root.h));
                points = pts;
            }

            Connections {
                target: root
                function onValuesChanged() { shape.rebuild(); }
            }

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 2
                strokeColor: Theme.accent
                fillGradient: LinearGradient {
                    x1: 0; y1: root.h - shape.peak
                    x2: 0; y2: root.h
                    GradientStop { position: 0; color: Qt.alpha(Theme.accent, 0.45) }
                    GradientStop { position: 1; color: Qt.alpha(Theme.accent, 0.05) }
                }
                PathPolyline { path: shape.points }
            }
        }
    }

    // Big version of the bar waveform, centered on screen
    Component {
        id: mirror

        // One bar per band on each side, sized to span the whole screen
        Row {
            readonly property int count: root.n * 2
            readonly property real barW: (root.w - spacing * (count + 1)) / count

            anchors.centerIn: parent
            spacing: 6

            Repeater {
                model: parent.count

                Rectangle {
                    required property int index

                    // Bass in the middle, highs out at both edges
                    readonly property real v: root.values[Math.floor(Math.abs(index - (root.n - 0.5)))] ?? 0

                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.barW
                    height: Math.max(width, v * root.h * 0.3)
                    radius: width / 2
                    color: Theme.accent
                    opacity: 0.5 + v * 0.5
                    Behavior on height { NumberAnimation { duration: 50 } }
                }
            }
        }
    }

    // Radial spectrum around the screen center, pulsing with the bass
    Component {
        id: ring

        Item {
            id: ringItem

            readonly property int count: 96
            readonly property real radius: root.h * (0.14 + Cava.bass * 0.015)

            anchors.fill: parent

            Rectangle {
                anchors.centerIn: parent
                width: ringItem.radius * 2 - 12
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(Theme.accent, 0.35 + Cava.bass * 0.5)
            }

            Repeater {
                model: ringItem.count

                Rectangle {
                    required property int index

                    // Mirrored left/right so the ring stays symmetric
                    readonly property real v: root.values[Math.round(Math.abs(index / ringItem.count * 2 - 1) * (root.n - 1))] ?? 0
                    readonly property real len: Math.max(4, v * root.h * 0.14)

                    x: root.w / 2 - width / 2
                    y: root.h / 2 - ringItem.radius - len
                    width: 4
                    height: len
                    radius: 2
                    color: Theme.accent
                    opacity: 0.5 + v * 0.5
                    transform: Rotation {
                        origin.x: 2
                        origin.y: ringItem.radius + len
                        angle: index / ringItem.count * 360 + 180
                    }
                }
            }
        }
    }

    // Trap Nation style: stacked smooth closed curves around the cover art, each layer
    // lagging a few frames behind the one in front, the whole thing kicking on the bass
    Component {
        id: nation

        Item {
            id: rings

            readonly property int layers: 6
            readonly property int lag: 2
            readonly property int res: 120
            // Mostly the low and mid bands, the top end is too quiet to shape the ring
            readonly property real span: (root.n - 1) * 0.75
            // Swells with the bass and punches out on kicks
            readonly property real pulse: 1 + Cava.bass * 0.1 + Cava.kick * 0.08
            readonly property real radius: root.h * 0.13 * pulse
            readonly property real amp: root.h * 0.12
            readonly property var player: Lyrics.player

            property var levels: []
            property var history: []
            property var paths: []

            // Ring geometry lives in a box around the centre, so the MSAA layer stays small
            readonly property real box: (root.h * 0.13 * 1.18 + amp + layers * 1.5) * 2 + 8
            // Static angle table: sin, cos and which band each sample reads
            readonly property var table: {
                const rows = [];
                for (let i = 0; i <= res; i++) {
                    const a = i / res * Math.PI * 2;
                    // 0 at the top, 1 at the bottom, mirrored left/right
                    rows.push({ s: Math.sin(a), c: Math.cos(a), m: (1 - Math.abs(i / res * 2 - 1)) * span });
                }
                return rows;
            }

            // Every layer has the same amplitude; they only differ by delay plus a hairline offset,
            // so colour shows just where the shape is moving
            function ringPath(lv, depth) {
                const c = box / 2, base = radius + depth * 1.5, a = amp;
                const pts = [];
                for (const r of table) {
                    const rad = base + root.spline(lv, r.m) * a;
                    pts.push(Qt.point(c + r.s * rad, c - r.c * rad));
                }
                return pts;
            }

            function rebuild() {
                // Smooth shape, but little easing over time so the ring moves snappily
                levels = root.smoothed(levels, 0.15);
                const h = [levels].concat(history).slice(0, layers * lag);
                history = h;
                const out = [];
                for (let k = 0; k < layers; k++)
                    out.push(ringPath(h[Math.min(k * lag, h.length - 1)], k));
                paths = out;
            }

            anchors.fill: parent

            Connections {
                target: root
                function onValuesChanged() { rings.rebuild(); }
            }

            Item {
                anchors.centerIn: parent
                width: rings.box
                height: rings.box
                layer.enabled: true
                layer.samples: 4

                // One shape for all layers, triangulated off the GUI thread.
                // Back to front: the most delayed, widest layer is drawn first.
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.GeometryRenderer
                    asynchronous: true

                    Ring { depth: 5 }
                    Ring { depth: 4 }
                    Ring { depth: 3 }
                    Ring { depth: 2 }
                    Ring { depth: 1 }
                    Ring { depth: 0 }
                }
            }

            component Ring: ShapePath {
                required property int depth

                strokeWidth: -1
                // Hues fan out from the accent, the classic rainbow stack kept in the house colour family
                fillColor: depth === 0 ? Theme.text
                    : Qt.hsla((Theme.accent.hslHue + depth * 0.06) % 1, Math.max(0.7, Theme.accent.hslSaturation), 0.62, 0.95 - depth * 0.08)
                PathPolyline { path: rings.paths[depth] ?? [] }
            }

            // Cover art, or an accent disc when the player has none
            Rectangle {
                anchors.centerIn: parent
                width: rings.radius * 2 + 2
                height: width
                radius: width / 2
                color: Theme.bg
                border.width: 3
                border.color: Theme.text

                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width / 2
                    color: Theme.surface

                    Image {
                        anchors.fill: parent
                        source: rings.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(512, 512)
                        asynchronous: true
                    }
                }
            }
        }
    }

    // Wide neon ribbons hanging down a back wall that fold in the lower third and run along
    // the floor towards the viewer, in real perspective. The ribbons never move; pulses fired by
    // onsets in each band travel along them as smooth mirrored bulges, entering at the top.
    Component {
        id: flow

        Item {
            id: ribbons

            readonly property int count: 4
            readonly property int res: 120
            // Frames the waveform takes to cross the whole ribbon
            readonly property int travel: 30
            readonly property real span: (root.n - 1) * 0.6

            // World units are screen heights; the camera looks down +z with focal length 1
            readonly property real horizon: 0.3
            readonly property real wall: 1
            readonly property real floorY: 0.38
            readonly property real ceiling: 0.36
            readonly property real near: 0.42
            readonly property real bend: 0.035
            readonly property real spread: 0.6
            readonly property real halfWidth: 0.045

            readonly property real wallLen: ceiling + floorY - bend
            readonly property real arcLen: bend * Math.PI / 2
            readonly property real floorLen: wall - bend - near
            readonly property real total: wallLen + arcLen + floorLen

            property var levels: []
            // Per-ribbon loudness and pulse history, newest first
            property var bodies: []
            property var pulses: []
            property var waves: []
            // Slow per-ribbon average and the decaying pulse fired when the band jumps above it
            property var average: []
            property var charge: []
            property var previous: []
            // Left and right edges of every ribbon, fixed
            readonly property var edges: {
                const out = [];
                for (let i = 0; i < count; i++)
                    out.push([strip(i, -halfWidth), strip(i, halfWidth)]);
                return out;
            }

            // Point on the centre line at arc fraction u, as [y, z]
            function along(u) {
                const d = u * total;
                if (d < wallLen)
                    return [ceiling - d, wall];
                if (d < wallLen + arcLen) {
                    const a = (d - wallLen) / bend;
                    return [-floorY + bend - bend * Math.sin(a), wall - bend + bend * Math.cos(a)];
                }
                return [-floorY, wall - bend - (d - wallLen - arcLen)];
            }

            function project(x, y, z) {
                return Qt.point(root.w / 2 + x / z * root.h, (horizon - y / z) * root.h);
            }

            function xOf(i) {
                return (i / (count - 1) * 2 - 1) * spread;
            }

            function strip(i, dx) {
                const pts = [];
                for (let j = 0; j <= res; j++) {
                    const [y, z] = along(j / res);
                    pts.push(project(xOf(i) + dx, y, z));
                }
                return pts;
            }

            // Static per-sample geometry: screen y, perspective scale, and where each sample reads
            // the history, so the per-frame loop is plain arithmetic
            readonly property var table: {
                const rows = [];
                for (let j = 0; j <= res; j++) {
                    const u = j / res;
                    const [y, z] = along(u);
                    const f = u * (travel - 1);
                    const k = Math.floor(f);
                    rows.push({ sy: (horizon - y / z) * root.h, scale: root.h / z, k: k, t: f - k });
                }
                return rows;
            }

            function rebuild() {
                levels = root.smoothed(levels, 0.3);
                const body = [], avg = [], chg = [], prev = [];
                for (let i = 0; i < count; i++) {
                    const lv = root.spline(levels, Math.abs(i / (count - 1) * 2 - 1) * span);
                    const a = average[i] ?? lv;
                    // An onset is the band rising this frame while above its own recent average,
                    // relative to it so quieter bands fire as often as loud ones. Rise only, so a
                    // sustained loud note fires once instead of stretching one long pulse.
                    const rise = lv - (previous[i] ?? lv);
                    const hit = lv > a * 1.1 ? Math.max(0, rise) / Math.max(0.08, a) * 6 : 0;
                    prev.push(lv);
                    // Fast decay keeps the tail short, so the bulge rises and falls within a few frames
                    chg.push(Math.min(1, Math.max((charge[i] ?? 0) * 0.54, hit)));
                    avg.push(a * 0.9 + lv * 0.1);
                    body.push(Math.pow(lv, 0.7) * 0.3);
                }
                average = avg;
                charge = chg;
                previous = prev;
                const hb = [body].concat(bodies).slice(0, travel);
                const hp = [chg].concat(pulses).slice(0, travel);
                bodies = hb;
                pulses = hp;

                const out = [];
                const rows = table, n = count, last = hb.length - 1, cx = root.w / 2;
                const hw = halfWidth * 0.92;
                for (let i = 0; i < n; i++) {
                    // Body and pulse summed per frame first: the spline is linear, so this is the same curve
                    const col = [];
                    for (let k = 0; k <= last; k++)
                        col.push(hb[k][i] + hp[k][i]);
                    const x0 = xOf(i);
                    const left = [], right = [];
                    for (const r of rows) {
                        const k = r.k, t = r.t;
                        const p0 = col[k > 0 ? k - 1 : 0], p1 = col[k < last ? k : last];
                        const p2 = col[k + 1 < last ? k + 1 : last], p3 = col[k + 2 < last ? k + 2 : last];
                        const v = 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);
                        // Soft saturation instead of a hard clamp, so strong pulses stay round instead of flat-sided
                        const half = (0.04 + Math.tanh(Math.max(0, v) * 1.3) * 0.96) * hw;
                        left.push(Qt.point(cx + (x0 - half) * r.scale, r.sy));
                        right.push(Qt.point(cx + (x0 + half) * r.scale, r.sy));
                    }
                    out.push(left.concat(right.reverse()));
                }
                waves = out;
            }

            anchors.fill: parent

            Connections {
                target: root
                function onValuesChanged() { ribbons.rebuild(); }
            }

            // Neon bloom, always on for this style
            layer.enabled: true
            layer.samples: 4
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.accent
                blurMax: 48
                shadowBlur: 1
                shadowOpacity: 1
            }

            Repeater {
                model: ribbons.count

                Shape {
                    required property int index
                    readonly property var edge: ribbons.edges[index]

                    anchors.fill: parent
                    // Paths change every frame: triangulate off the GUI thread; the bloom layer's MSAA smooths edges
                    preferredRendererType: Shape.GeometryRenderer
                    asynchronous: true

                    // The ribbon itself: a faint band, faded in from the top
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: LinearGradient {
                            x1: 0; y1: 0
                            x2: 0; y2: root.h * 0.5
                            GradientStop { position: 0; color: Qt.alpha(Theme.accent, 0) }
                            GradientStop { position: 1; color: Qt.alpha(Theme.accent, 0.14) }
                        }
                        PathPolyline { path: edge[0].concat(edge[1].slice().reverse()) }
                    }

                    // The waveform racing along it
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Theme.text
                        fillGradient: LinearGradient {
                            x1: 0; y1: 0
                            x2: 0; y2: root.h * 0.4
                            GradientStop { position: 0; color: Qt.alpha(Theme.accent, 0) }
                            GradientStop { position: 1; color: Qt.alpha(Theme.accent, 0.9) }
                        }
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline { path: ribbons.waves[index] ?? [] }
                    }
                }
            }
        }
    }
}
