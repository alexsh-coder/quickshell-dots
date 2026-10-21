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
        // Plain JS copies: indexing a list property directly re-reads the whole list every time
        const vals = Array.from(values), ker = Array.from(kernel);
        const half = (ker.length - 1) / 2;
        const out = [];
        for (let i = 0; i < n; i++) {
            let s = 0;
            for (let k = 0; k < ker.length; k++) {
                // Reflect at the ends, the curves continue into their mirrored half
                let j = Math.abs(i + k - half);
                if (j >= n)
                    j = 2 * n - 2 - j;
                s += (vals[j] ?? 0) * ker[k];
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

    // Spectral flux onset detection: the summed rise of cur over prev across a band range, against an
    // adaptive threshold; d is the detector's state, b its bands. Straight from the raw spectrum, so
    // hits fire without smoothing lag. Returns a pulse that jumps on a hit and decays quickly.
    function onset(d, b, cur, prev) {
        let f = 0;
        for (let j = b.lo; j < b.hi; j++)
            f += Math.max(0, cur[j] - prev[j]);
        f /= b.hi - b.lo;
        const threshold = d.mean * 2 + b.floor;
        d.mean = d.mean * 0.9 + f * 0.1;
        d.peak = Math.max(f, d.peak * 0.997);
        d.age++;
        let hit = 0;
        // Strength relative to recent peaks, so loud and soft hits differ. After a refractory
        // gap a new hit fires; right after one the same hit keeps growing to its peak.
        if (f > threshold && (d.age > 6 || d.age < 3)) {
            hit = f / d.peak * (b.gain ?? 1);
            if (d.age > 6)
                d.age = 0;
        }
        d.charge = Math.min(1, Math.max(d.charge * 0.6, hit));
        return d.charge;
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
    // averaging over more frames than the one in front, the whole thing kicking on the bass
    Component {
        id: nation

        Item {
            id: rings

            readonly property int layers: 6
            // Frames of extra averaging per layer: more is a longer, lazier tail
            readonly property real lag: 1
            readonly property int res: 120
            // Mostly the low and mid bands, the top end is too quiet to shape the ring
            readonly property real span: (root.n - 1) * 0.75
            // Swells with the bass and punches out on kicks
            readonly property real pulse: 1 + Cava.bass * 0.1 + Cava.kick * 0.08
            readonly property real radius: root.h * 0.13 * pulse
            readonly property real amp: root.h * 0.12
            // Each layer reaches a bit further on peaks, so colour opens up where the music hits
            readonly property real spread: 0.06
            // Hairline gap between layers at rest, in px
            readonly property real gap: 1
            readonly property var player: Lyrics.player

            // Palette by distance outside the white ring: a pale tint, then the wallpaper's hues in neon,
            // each owning a stretch matching its share of the image. Hues go dominant first, then nearest hue,
            // and blend in OKLab so hand-offs pass through soft in-between tones instead of a rainbow
            readonly property int stopCount: 12
            readonly property var stops: {
                const hd = (a, b) => Math.abs((a - b + 540) % 360 - 180);
                const pal = Accent.palette.length ? Accent.palette.slice(0, 6) : [{ w: 1, h: Accent.toOklch(Theme.accent)[2] }];
                const order = [pal[0]], rest = pal.slice(1);
                while (rest.length) {
                    const last = order[order.length - 1].h;
                    rest.sort((a, b) => hd(a.h, last) - hd(b.h, last));
                    order.push(rest.shift());
                }
                const lab = ([L, C, H]) => [L, C * Math.cos(H * Math.PI / 180), C * Math.sin(H * Math.PI / 180)];
                const neons = order.map(g => lab(Accent.neon(g.h)));
                const pale = lab([0.93, 0.08, order[0].h]);
                const ends = [];
                order.reduce((acc, g) => (ends.push(acc + g.w), acc + g.w), 0);
                const sig = x => 1 / (1 + Math.exp(-x / 0.06));
                const paleZone = 0.06;
                const out = [];
                for (let k = 0; k < stopCount; k++) {
                    const t = k / (stopCount - 1);
                    let c;
                    if (t < paleZone) {
                        c = pale.map((v, j) => v + (neons[0][j] - v) * t / paleZone);
                    } else {
                        // Soft-edged span per hue, normalised so the weights always sum to one
                        const u = (t - paleZone) / (1 - paleZone);
                        const w = ends.map((e, i) => (i ? sig(u - ends[i - 1]) : 1) * (i < ends.length - 1 ? sig(e - u) : 1));
                        const sum = w.reduce((a, b) => a + b);
                        c = [0, 1, 2].map(j => w.reduce((acc, wi, i) => acc + wi * neons[i][j], 0) / sum);
                    }
                    out.push(Accent.fromOklch(c[0], Math.hypot(c[1], c[2]), Math.atan2(c[2], c[1]) * 180 / Math.PI));
                }
                return out;
            }
            // Distance outside the white ring, in px, at which the palette runs out
            readonly property real reach: amp * 0.25

            property var levels: []
            property var history: []
            property var paths: []

            // Ring geometry lives in a box around the centre, so the MSAA layer stays small
            readonly property real box: (root.h * 0.13 * 1.18 + amp * (1 + layers * spread) + layers * gap) * 2 + 8
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

            // Layers differ by averaging window, a slightly larger amplitude and a hairline offset,
            // so colour shows mostly where the shape is moving or peaking
            function ringPath(lv, depth) {
                const c = box / 2, base = radius + depth * gap, a = amp * (1 + depth * spread);
                const pts = [];
                for (const r of table) {
                    const rad = base + root.spline(lv, r.m) * a;
                    pts.push(Qt.point(c + r.s * rad, c - r.c * rad));
                }
                return pts;
            }

            function rebuild() {
                // Smooth shape, but little easing over time so the ring moves snappily
                levels = root.smoothed(levels, 0.05);
                const h = [levels].concat(history).slice(0, Math.round((layers - 1) * lag) + 1);
                history = h;
                // Layer k is a moving average over the last round(k * lag) + 1 frames (SnGmng's AverageSize):
                // the front ring stays sharp, the ones behind lag and soften into a halo
                const sum = new Array(root.n).fill(0);
                const out = [];
                let f = 0;
                for (let k = 0; k < layers; k++) {
                    const end = Math.min(Math.round(k * lag) + 1, h.length);
                    for (; f < end; f++)
                        for (let i = 0; i < root.n; i++)
                            sum[i] += h[f][i] ?? 0;
                    out.push(ringPath(sum.map(s => s / f), k));
                }
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

                // Layers are drawn as a mask and coloured by halo.frag, see there
                layer.effect: ShaderEffect {
                    readonly property size size: Qt.size(width, height)
                    readonly property real reach: rings.reach
                    readonly property var palette: strip

                    fragmentShader: Qt.resolvedUrl("../../shaders/halo.frag.qsb")
                }

                // One shape for all layers, on the curve renderer: the geometry renderer either triangulates
                // on the GUI thread, which starves the JS GC at 60 fps, or on a worker thread, which raced with
                // per-frame path updates and segfaulted inside QtQuick.Shapes.
                // Back to front: the most delayed, widest layer is drawn first.
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

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
                // Mask for halo.frag: green marks the white ring
                fillColor: depth === 0 ? Qt.rgba(0, 1, 0, 1) : Qt.rgba(1, 0, 0, 1)
                PathPolyline { path: rings.paths[depth] ?? [] }
            }

            // Palette as a strip texture for halo.frag
            Rectangle {
                id: paletteStrip
                width: 64
                height: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    Stop { k: 0 }
                    Stop { k: 1 }
                    Stop { k: 2 }
                    Stop { k: 3 }
                    Stop { k: 4 }
                    Stop { k: 5 }
                    Stop { k: 6 }
                    Stop { k: 7 }
                    Stop { k: 8 }
                    Stop { k: 9 }
                    Stop { k: 10 }
                    Stop { k: 11 }
                }
            }

            ShaderEffectSource {
                id: strip
                sourceItem: paletteStrip
                hideSource: true
                width: 0
                height: 0
            }

            component Stop: GradientStop {
                required property int k

                position: k / (rings.stopCount - 1)
                color: rings.stops[k] ?? Theme.accent
            }

            // Cover art, or an accent disc when the player has none
            Rectangle {
                anchors.centerIn: parent
                width: rings.radius * 2 + 2
                height: width
                radius: width / 2
                color: Theme.bg
                border.width: 3
                border.color: "#ffffff"

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

    // Recent per-column values as a ring-buffer texture for the shader styles: one row per frame,
    // row `head` the newest. Only new rows are drawn: writing Canvas ImageData pixel by pixel goes
    // through a slow per-pixel call, a few dozen fillRects are cheap.
    component History: Item {
        id: hist

        required property int cols
        required property int rows
        property int head: 0
        property var pending: []
        readonly property var texture: ShaderEffectSource {
            sourceItem: canvas
            hideSource: true
            smooth: true
            wrapMode: ShaderEffectSource.Repeat
            textureSize: Qt.size(hist.cols, hist.rows)
        }

        // One [r, g, b] in 0..1 per column
        function push(row) {
            head = (head + rows - 1) % rows;
            pending.push({ at: head, row: row });
            canvas.requestPaint();
        }

        Canvas {
            id: canvas

            width: hist.cols
            height: hist.rows
            renderTarget: Canvas.Image
            onPaint: {
                const ctx = getContext("2d");
                for (const p of hist.pending) {
                    for (let c = 0; c < hist.cols; c++) {
                        const [r, g, b] = p.row[c];
                        ctx.fillStyle = `rgb(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)})`;
                        ctx.fillRect(c, p.at, 1, 1);
                    }
                }
                hist.pending = [];
            }
        }
    }

    // Flat spectrogram of neon ribbons, one per frequency band with the bass at the bottom. Time runs
    // out from the centre: the live sound is born in the middle and drifts to both edges, and hits in
    // each band fire pulses that race outwards along its ribbon. Drawn by ribbons.frag.
    Component {
        id: flow

        Item {
            id: strip

            readonly property int count: 7
            readonly property int rows: 100
            // Log-spaced cava bands grouped per ribbon, bottom first
            readonly property var bands: Array.from({ length: count }, (_, k) => {
                const lo = Math.floor(k * root.n / count * 0.85), hi = Math.floor((k + 1) * root.n / count * 0.85);
                return { lo: lo, hi: Math.max(lo + 1, hi), floor: 0.02 };
            })
            readonly property var detectors: bands.map(() => ({ mean: 0, peak: 0.05, age: 99, charge: 0 }))
            property var raw: []
            property var average: []

            function rebuild() {
                const cur = Array.from(root.values), prev = raw.length === root.n ? raw : cur;
                const row = [], avg = [];
                for (let k = 0; k < count; k++) {
                    const b = bands[k];
                    let lv = 0;
                    for (let j = b.lo; j < b.hi; j++)
                        lv += cur[j];
                    lv /= b.hi - b.lo;
                    // Relative to the band's own average, so every ribbon moves, not just the loud bass
                    const a = average[k] ?? lv;
                    avg.push(a * 0.98 + lv * 0.02);
                    const body = Math.tanh(lv * Math.pow(lv / (a + 0.05), 1.5) * 1.2);
                    row.push([body, root.onset(detectors[k], b, cur, prev), 0]);
                }
                raw = cur;
                average = avg;
                trail.push(row);
            }

            anchors.fill: parent

            Connections {
                target: root
                function onValuesChanged() { strip.rebuild(); }
            }

            History {
                id: trail

                cols: strip.count
                rows: strip.rows
            }

            ShaderEffect {
                // Lane layout in screen heights, from the bottom ribbon up
                readonly property real aspect: width / height
                readonly property real pixel: 1 / height
                readonly property real laneBase: 0.9
                readonly property real laneGap: 0.045
                readonly property real lanes: strip.count
                readonly property real halfSpan: aspect * 0.48
                readonly property real head: trail.head
                readonly property real rows: strip.rows
                readonly property color accent: Theme.accent
                readonly property color highlight: Theme.text
                readonly property var history: trail.texture

                anchors.fill: parent
                fragmentShader: Qt.resolvedUrl("../../shaders/ribbons.frag.qsb")
            }
        }
    }

    // Legacy, not in the style list. Spectrogram terrain in the spirit of Unknown Pleasures: the recent spectrum lies on a floor as a
    // smooth glowing landscape receding to the horizon. The front edge is the live spectrum, the past
    // scrolls away frame by frame, and hits light the ground up so the beat ripples into the distance.
    // History goes to the GPU as a small ring-buffer texture and terrain.frag ray-marches it.
    Component {
        id: terrain

        Item {
            id: field

            // Texture size: columns across half the width (mirrored in the shader), one row per frame
            readonly property int cols: 40
            readonly property int rows: 90
            readonly property real span: (root.n - 1) * 0.8

            // Hits light the ground up: the kick from the low bands, snares and claps from broadband flux
            readonly property var bands: [{ lo: 16, hi: 40, floor: 0.01, gain: 0.7 }, { lo: 0, hi: 6, floor: 0.03, gain: 1 }]
            readonly property var detectors: bands.map(() => ({ mean: 0, peak: 0.05, age: 99, charge: 0 }))
            property var raw: []
            property var levels: []
            // Slow per-band average, each band is shown relative to it so the whole width has relief
            property var average: []

            function profile() {
                const rel = [], avg = [];
                for (let i = 0; i < root.n; i++) {
                    const a = average[i] ?? levels[i];
                    avg.push(a * 0.98 + levels[i] * 0.02);
                    // Bands rising above their own average stand out. Soft saturation keeps loud peaks
                    // round instead of flat-topped, the power keeps quiet parts flat.
                    rel.push(Math.pow(Math.tanh(levels[i] * Math.pow(levels[i] / (a + 0.05), 1.5) * 1.6), 1.1));
                }
                average = avg;
                const out = [];
                for (let c = 0; c < cols; c++)
                    out.push(root.spline(rel, c / (cols - 1) * span));
                return out;
            }

            function rebuild() {
                levels = root.smoothed(levels, 0.2);
                const cur = Array.from(root.values), prev = raw.length === root.n ? raw : cur;
                let glow = 0;
                for (let p = 0; p < bands.length; p++)
                    glow = Math.max(glow, root.onset(detectors[p], bands[p], cur, prev));
                raw = cur;

                const row = profile();
                // Height as high and low bytes in red and blue, the glow in green
                trail.push(row.map(v => {
                    const x = Math.min(1, v) * 255, hi = Math.floor(x);
                    return [hi / 255, glow, Math.round((x - hi) * 255) / 255];
                }));
            }

            anchors.fill: parent

            Connections {
                target: root
                function onValuesChanged() { field.rebuild(); }
            }

            History {
                id: trail

                cols: field.cols
                rows: field.rows
            }

            ShaderEffect {
                // World units are screen heights; the camera looks down +z with focal length 1
                readonly property real aspect: width / height
                readonly property real pixel: 1 / height
                readonly property real horizon: 0.56
                readonly property real eye: 0.4
                readonly property real amp: 0.3
                readonly property real halfWidth: 0.85
                readonly property real zNear: 1
                readonly property real zFar: 4.4
                readonly property real head: trail.head
                readonly property real rows: field.rows
                readonly property color accent: Theme.accent
                readonly property color highlight: Theme.text
                readonly property color shade: Theme.bg
                readonly property var history: trail.texture

                anchors.fill: parent
                fragmentShader: Qt.resolvedUrl("../../shaders/terrain.frag.qsb")
            }
        }
    }
}
