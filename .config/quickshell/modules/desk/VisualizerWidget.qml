import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.services

// Music visualizer filling its widget rect. Strips (bars, wave, mirror) span the rect; round styles
// (ring, nation) sit in its centre, sized by its shorter side; particles fly out of its centre
Item {
    id: root

    property var cfg: ({})
    // Screen height: sizes are relative to it, so a style looks the same in any rect
    property real sh: 1080
    property bool active: false

    readonly property string style: cfg.style ?? "bars"
    readonly property color ink: Theme.paint(cfg.color)
    readonly property real gain: (cfg.gain ?? 1)
    // Plain JS array: per-bar bindings index it, and indexing a list property copies the whole list
    readonly property var values: Cava.values.map(v => Math.min(1, v * gain))
    readonly property int n: Cava.bars
    // Bars and mirror: the spectrum stretched or squeezed to the chosen count
    readonly property int count: Math.max(2, Math.round(cfg.count ?? n))
    readonly property var resampled: {
        if (style !== "bars" && style !== "mirror")
            return [];
        const v = values, out = [];
        for (let i = 0; i < count; i++) {
            const m = i / (count - 1) * (n - 1), j = Math.floor(m), f = m - j;
            out.push((v[j] ?? 0) * (1 - f) + (v[Math.min(j + 1, n - 1)] ?? 0) * f);
        }
        return out;
    }
    readonly property real gap: cfg.gap ?? 6
    readonly property bool solid: cfg.fill === "solid"
    readonly property real w: width
    readonly property real h: height
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    // Round styles: 1 when the rect's shorter side is 0.6 screen heights
    readonly property real k: Math.min(width, height) / (sh * 0.6)
    readonly property bool fromTop: cfg.align === "top"
    // Gaussian over neighbouring bars, so curves roll instead of spiking
    readonly property list<real> kernel: [0.05, 0.12, 0.2, 0.26, 0.2, 0.12, 0.05]

    // Spatial blur of the spectrum, eased against the previous frame
    function smoothed(prev, ease, kern) {
        // Plain JS copies: indexing a list property directly re-reads the whole list every time
        const vals = Array.from(values), ker = Array.from(kern ?? kernel);
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

    // Halo on the bass: the preset's glow, or the ring's own switch (lights its text and art too)
    layer.enabled: active && (MusicFx.glow || (style === "ring" && !!cfg.ringGlow))
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.ink
        shadowBlur: 1
        shadowOpacity: Math.min(1, (0.35 + Cava.bass * 0.65) * (MusicFx.glow ? MusicFx.gain("glow") : 1))
        shadowScale: 1.02
    }

    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: ({ bars: bars, wave: wave, mirror: mirror, ring: ring, nation: nation, particles: particles })[root.style] ?? null
    }

    // Spectrum along the bottom (or top) of the rect
    Component {
        id: bars

        Item {
            Row {
                id: strip

                readonly property real barW: Math.max(1, (root.w - spacing * (root.count - 1)) / root.count)

                height: root.h
                spacing: Math.min(root.gap, root.w / root.count * 0.8)

                Repeater {
                    model: root.count

                    Rectangle {
                        required property int index
                        readonly property real v: root.resampled[index] ?? 0

                        y: root.fromTop ? 0 : strip.height - height
                        width: strip.barW
                        height: Math.max(4, v * root.h)
                        radius: width / 2 * (root.cfg.round ?? 1)
                        color: Qt.alpha(root.ink, root.solid ? 1 : 0.35 + v * 0.5)
                        Behavior on height { NumberAnimation { duration: root.cfg.ease ?? 50 } }
                    }
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
            readonly property real peak: root.h - 4
            property var levels: []
            property var points: []

            // Mirrored around the center, bass in the middle
            function sample(t) {
                return root.spline(levels, Math.abs(t * 2 - 1) * (root.n - 1));
            }

            function rebuild() {
                levels = root.smoothed(levels, root.cfg.smooth ?? 0.55);
                // Hanging from the top edge when the widget says so
                const base = root.fromTop ? 0 : root.h, dir = root.fromTop ? 1 : -1;
                const pts = [Qt.point(0, base)];
                for (let i = 0; i <= res; i++) {
                    const t = i / res;
                    pts.push(Qt.point(t * root.w, base + dir * (4 + sample(t) * peak)));
                }
                pts.push(Qt.point(root.w, base));
                points = pts;
            }

            Connections {
                target: root
                function onValuesChanged() { shape.rebuild(); }
            }

            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: root.cfg.thickness ?? 2
                strokeColor: (root.cfg.thickness ?? 2) > 0 ? root.ink : "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: root.fromTop ? shape.peak : root.h - shape.peak
                    x2: 0; y2: root.fromTop ? 0 : root.h
                    GradientStop { position: 0; color: Qt.alpha(root.ink, root.cfg.fillAlpha ?? 0.45) }
                    GradientStop { position: 1; color: Qt.alpha(root.ink, (root.cfg.fillAlpha ?? 0.45) / 9) }
                }
                PathPolyline { path: shape.points }
            }
        }
    }

    // Bars growing both ways from the middle line, bass in the centre
    Component {
        id: mirror

        Item {
            Row {
                id: pairs

                // One bar per band on each side
                readonly property int count: root.count * 2
                readonly property real barW: Math.max(1, (root.w - spacing * (count - 1)) / count)

                height: root.h
                spacing: Math.min(root.gap, root.w / count * 0.8)

                Repeater {
                    model: pairs.count

                    Rectangle {
                        required property int index

                        // Bass in the middle, highs out at both edges
                        readonly property real v: root.resampled[Math.floor(Math.abs(index - (root.count - 0.5)))] ?? 0

                        anchors.verticalCenter: parent.verticalCenter
                        width: pairs.barW
                        height: Math.max(width, v * root.h)
                        radius: width / 2 * (root.cfg.round ?? 1)
                        color: root.ink
                        opacity: root.solid ? 1 : 0.5 + v * 0.5
                        Behavior on height { NumberAnimation { duration: root.cfg.ease ?? 50 } }
                    }
                }
            }
        }
    }

    // Radial spectrum, pulsing with the bass
    Component {
        id: ring

        Item {
            id: ringItem

            readonly property int count: Math.round(root.cfg.ringCount ?? 96)
            readonly property real spike: root.cfg.ringWidth ?? 4
            readonly property real radius: root.sh * (0.14 * (root.cfg.ringSize ?? 1) + Cava.bass * 0.015) * root.k

            Rectangle {
                visible: root.cfg.ringLine ?? true
                x: root.cx - width / 2
                y: root.cy - height / 2
                width: ringItem.radius * 2 - 12
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(root.ink, 0.35 + Cava.bass * 0.5)
            }

            // What sits in the hole: art, track info, lyrics, a clock or a bass-driven disc
            Item {
                id: center

                readonly property string mode: root.cfg.ringCenter ?? "none"
                readonly property var player: Lyrics.player
                readonly property bool hasArt: ["cover", "cover+title", "vinyl"].includes(mode)
                readonly property bool hasText: ["title", "cover+title"].includes(mode)
                readonly property real d: ringItem.radius * 2 - ((root.cfg.ringLine ?? true) ? 24 : 12)
                // Hole size without the bass pulse
                readonly property real rest: root.sh * 0.14 * (root.cfg.ringSize ?? 1) * root.k * 2 - ((root.cfg.ringLine ?? true) ? 24 : 12)
                property date now: new Date()

                // Greedy word wrap measured at the resting font size; the last line gets an ellipsis.
                // FontMetrics methods at a fixed 100 px, scaled: no properties written, so no binding loops
                function wrap(str, px, maxW, maxLines, bold) {
                    const fm = bold ? boldMetrics : metrics;
                    const limit = maxW * 100 / Math.max(7, px);
                    const lines = [];
                    let cur = "";
                    for (const w of str.split(/\s+/).filter(x => x)) {
                        const next = cur ? cur + " " + w : w;
                        if (!cur || fm.advanceWidth(next) <= limit)
                            cur = next;
                        else {
                            lines.push(cur);
                            cur = w;
                        }
                    }
                    if (cur)
                        lines.push(cur);
                    const out = lines.slice(0, maxLines);
                    if (out.length)
                        out[out.length - 1] = fm.elidedText(lines.slice(out.length - 1).join(" "), Qt.ElideRight, limit);
                    return out.join("\n");
                }

                FontMetrics {
                    id: metrics
                    font.family: Theme.font
                    font.pixelSize: 100
                }

                FontMetrics {
                    id: boldMetrics
                    font.family: Theme.font
                    font.pixelSize: 100
                    font.bold: true
                }

                component LyricSlot: Text {
                    property bool on
                    property string line
                    property real t: on ? 1 : 0

                    Behavior on t { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    anchors.centerIn: parent
                    visible: t > 0
                    opacity: Math.max(0, 2 * t - 1)
                    horizontalAlignment: Text.AlignHCenter
                    text: center.wrap(line, center.rest * 0.09, center.rest * 0.8, 4, false)
                    color: root.ink
                    font.family: Theme.font
                    font.pixelSize: Math.max(8, center.rest * 0.09)
                }

                visible: mode !== "none"
                x: root.cx - d / 2
                y: root.cy - d / 2
                width: d
                height: d

                ClippingRectangle {
                    visible: center.hasArt
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.alpha(root.ink, 0.15)

                    Cover {
                        anchors.fill: parent
                        player: center.player
                        rotation: center.mode === "vinyl" ? spin.angle : 0
                    }

                    // Darkens the art so the text on top stays readable
                    Rectangle {
                        visible: center.mode === "cover+title"
                        anchors.fill: parent
                        color: Qt.alpha("#000000", 0.45)
                    }
                }

                // Vinyl: grooves and a spindle hole over the spinning art
                Repeater {
                    model: center.mode === "vinyl" ? 3 : 0

                    Rectangle {
                        required property int index

                        anchors.centerIn: parent
                        width: center.d * (0.92 - index * 0.14)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha("#000000", 0.25)
                    }
                }

                Rectangle {
                    visible: center.mode === "vinyl"
                    anchors.centerIn: parent
                    width: center.d * 0.1
                    height: width
                    radius: width / 2
                    color: Theme.bg
                    border.width: 2
                    border.color: Qt.alpha(root.ink, 0.6)
                }

                FrameAnimation {
                    id: spin
                    property real angle: 0
                    running: center.mode === "vinyl" && root.active && (center.player?.isPlaying ?? false)
                    // 33 rpm, nudged by the bass
                    onTriggered: angle = (angle + frameTime * 200 * (1 + Cava.bass * 0.6)) % 360
                }

                // Every text mode lives here: laid out once at the resting size, so the ring's pulse never
                // reflows or resizes it. The beat shows as a tremble instead: a jitter that spikes on kicks
                // and hums on the bass, plus an accent ghost split off sideways
                Item {
                    id: shaker

                    readonly property real energy: Math.min(1, Cava.kick + Cava.bass * 0.35)
                    property real jx: 0
                    property real jy: 0
                    property real jr: 0

                    visible: center.hasText || ["lyrics", "clock", "progress"].includes(center.mode)
                    width: center.d
                    height: center.d
                    transform: [
                        Rotation { origin.x: shaker.width / 2; origin.y: shaker.height / 2; angle: shaker.jr },
                        Translate { x: shaker.jx; y: shaker.jy }
                    ]
                    layer.enabled: visible && root.active
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowBlur: 0.15
                        shadowColor: center.mode === "cover+title" ? root.ink : Theme.secondary
                        shadowOpacity: Math.min(0.8, Cava.kick * 1.2)
                        shadowHorizontalOffset: center.rest * 0.018 * Cava.kick
                        shadowVerticalOffset: 0
                    }

                    FrameAnimation {
                        running: root.active && shaker.visible
                        onTriggered: {
                            const amp = center.rest * 0.012 * shaker.energy;
                            // A new random target every frame, eased into, so it trembles rather than teleports
                            const ease = Math.min(1, frameTime * 30);
                            shaker.jx += ((Math.random() * 2 - 1) * amp - shaker.jx) * ease;
                            shaker.jy += ((Math.random() * 2 - 1) * amp - shaker.jy) * ease;
                            shaker.jr += ((Math.random() * 2 - 1) * 1.5 * shaker.energy - shaker.jr) * ease;
                        }
                    }
                }

                // Lines are broken at the resting size and then drawn unwrapped, so the font can pulse
                // with the bass without words jumping between lines
                Column {
                    parent: shaker
                    visible: center.hasText
                    anchors.centerIn: parent
                    spacing: center.rest * 0.02

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: center.wrap(center.player?.trackTitle ?? "", center.rest * 0.1, center.rest * 0.78, 2, true)
                        color: center.mode === "cover+title" ? "#ffffff" : root.ink
                        font.family: Theme.font
                        font.pixelSize: Math.max(8, center.rest * 0.1)
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: center.wrap(center.player?.trackArtist ?? "", center.rest * 0.07, center.rest * 0.78, 1, false)
                        color: center.mode === "cover+title" ? "#ffffff" : root.ink
                        opacity: 0.7
                        font.family: Theme.font
                        font.pixelSize: Math.max(7, center.rest * 0.07)
                    }
                }

                // Track position as an arc, the time in the middle
                Shape {
                    visible: center.mode === "progress"
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(root.ink, 0.2)
                        strokeWidth: 3
                        PathAngleArc { centerX: center.d / 2; centerY: center.d / 2; radiusX: center.d / 2 - 4; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.ink
                        strokeWidth: 3
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: center.d / 2
                            centerY: center.d / 2
                            radiusX: center.d / 2 - 4
                            radiusY: radiusX
                            startAngle: -90
                            sweepAngle: 360 * progressTick.frac
                        }
                    }
                }

                FrameAnimation {
                    id: progressTick
                    property real frac: 0
                    property real pos: 0
                    running: center.mode === "progress" && root.active
                    onTriggered: {
                        const p = center.player;
                        pos = p?.position ?? 0;
                        frac = p && p.length > 0 ? Math.min(1, pos / p.length) : 0;
                    }
                }

                Text {
                    parent: shaker
                    visible: center.mode === "progress" || center.mode === "clock"
                    anchors.centerIn: parent
                    text: center.mode === "clock" ? Qt.formatTime(center.now, "hh:mm")
                        : Math.floor(progressTick.pos / 60) + ":" + String(Math.floor(progressTick.pos % 60)).padStart(2, "0")
                    color: root.ink
                    font.family: Theme.font
                    font.pixelSize: Math.max(8, center.rest * (center.mode === "clock" ? 0.22 : 0.16))
                    font.weight: Font.Light
                }

                Timer {
                    running: center.mode === "clock" && root.active
                    interval: 1000
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: center.now = new Date()
                }

                // Lyrics: the old line fades out, then the new one fades in
                Item {
                    id: lyricStage

                    parent: shaker

                    readonly property string target: center.mode === "lyrics" ? (Lyrics.lines[Lyrics.index]?.text ?? center.player?.trackTitle ?? "") : ""
                    property bool flip: false

                    visible: center.mode === "lyrics"
                    anchors.fill: parent

                    onTargetChanged: {
                        (flip ? lyricB : lyricA).line = target;
                        flip = !flip;
                    }

                    LyricSlot { id: lyricA; on: lyricStage.flip }
                    LyricSlot { id: lyricB; on: !lyricStage.flip }
                }

                // Solid disc breathing with the bass, flashing on kicks
                Rectangle {
                    visible: center.mode === "pulse"
                    anchors.centerIn: parent
                    width: center.d * (0.55 + Cava.bass * 0.35)
                    height: width
                    radius: width / 2
                    color: root.ink
                    opacity: 0.25 + Cava.kick * 0.6
                }
            }

            Repeater {
                model: ringItem.count

                Rectangle {
                    required property int index

                    // Mirrored left/right so the ring stays symmetric
                    readonly property real v: root.values[Math.round(Math.abs(index / ringItem.count * 2 - 1) * (root.n - 1))] ?? 0
                    readonly property real len: Math.max(4, v * root.sh * 0.14 * root.k)

                    x: root.cx - width / 2
                    y: root.cy - ringItem.radius - len
                    width: ringItem.spike
                    height: len
                    radius: width / 2
                    color: root.ink
                    opacity: 0.5 + v * 0.5
                    transform: Rotation {
                        origin.x: ringItem.spike / 2
                        origin.y: ringItem.radius + len
                        angle: index / ringItem.count * 360 + 180
                    }
                }
            }
        }
    }

    // Trap Nation style, rebuilt the way their After Effects template works: a linear 15-110 Hz spectrum
    // bent into a circle and mirrored, top to bottom. Each layer is the same spectrum over a shorter FFT
    // window, so the coloured ones behind the white ring are snappier and reach a bit further.
    // Spectrum comes from scripts/nation-fft.py; the ears are simply wherever the kick and 808 sit.
    Component {
        id: nation

        Item {
            id: rings

            readonly property int layers: 6
            readonly property int res: 240
            // Swells with the bass and punches out on kicks
            readonly property real pulse: 1 + Cava.bass * 0.1 + Cava.kick * 0.08
            readonly property real radius: root.sh * 0.13 * pulse * root.k
            // Spectrum height in ring radii at full level
            readonly property real lift: 1.45
            // Soft ceiling in ring radii: small bumps grow as they are, long lobes level off near it
            readonly property real ceiling: 0.9
            // Each layer behind reaches this much further. The template goes 700 to 1100 over 9 copies, but
            // its glow eats most of that; on screen the coloured edge stays thin
            readonly property real spread: 0.03
            // Hairline gap between layers at rest, in px
            readonly property real gap: 0.5
            readonly property var player: Lyrics.player

            // Palette by distance outside the white ring: a pale tint, then the wallpaper's hues in neon,
            // each owning a stretch matching its share of the image. Hues go dominant first, then nearest hue,
            // and blend in OKLab so hand-offs pass through soft in-between tones instead of a rainbow
            readonly property int stopCount: 12
            readonly property var stops: {
                if (Accent.mono || (root.cfg.color ?? "auto") !== "auto")
                    return Array(stopCount).fill(root.ink);
                const hd = (a, b) => Math.abs((a - b + 540) % 360 - 180);
                const pal = Accent.palette.length ? Accent.palette.slice(0, 6) : [{ w: 1, h: Accent.toOklch(root.ink)[2] }];
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
            readonly property real reach: root.sh * 0.03 * root.k

            property var paths: []

            // Ring geometry lives in a box around the centre, so the MSAA layer stays small
            readonly property real box: (root.sh * 0.13 * root.k * 1.18 * (2 + lift * (1 + (layers - 1) * spread)) + layers * gap) * 2 + 8
            // Static angle table: sin, cos and where along the spectrum each sample reads (0 top, 1 bottom)
            readonly property var table: {
                const rows = [];
                for (let i = 0; i < res; i++) {
                    const a = i / res * Math.PI * 2;
                    rows.push({ s: Math.sin(a), c: Math.cos(a), t: 1 - Math.abs(i / res * 2 - 1) });
                }
                return rows;
            }
            // Triangle blur around the circle, standing in for the template's glow-softened edges
            readonly property var blur: [1, 2, 3, 4, 5, 4, 3, 2, 1].map(w => w / 25)

            function ringPath(spec, depth) {
                const c = box / 2, base = radius + depth * gap, reachPx = radius * lift * (1 + depth * spread);
                const capPx = radius * ceiling * (1 + depth * spread);
                const last = spec.length - 1, disp = [];
                for (const r of table) {
                    const m = r.t * last, k = Math.min(last - 1, Math.floor(m));
                    const v = spec[k] + (spec[k + 1] - spec[k]) * (m - k);
                    disp.push(capPx * (1 - Math.exp(-v * reachPx / capPx)));
                }
                const pts = [];
                for (let i = 0; i <= res; i++) {
                    let d = 0;
                    for (let j = 0; j < blur.length; j++)
                        d += disp[(i + j - 4 + res) % res] * blur[j];
                    const rad = base + d, r = table[i % res];
                    pts.push(Qt.point(c + r.s * rad, c - r.c * rad));
                }
                return pts;
            }

            function feed(line) {
                const specs = line.split("|").map(l => l.split(";").map(v => Number(v) / 1000 * root.gain));
                if (specs.length !== layers || specs.some(sp => sp.length < 2))
                    return;
                paths = specs.map((sp, k) => ringPath(sp, k));
            }

            Process {
                running: root.active
                command: ["python3", Quickshell.shellDir + "/scripts/nation-fft.py"]
                stdout: SplitParser {
                    onRead: data => rings.feed(data)
                }
            }

            Item {
                x: root.cx - width / 2
                y: root.cy - height / 2
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
                color: rings.stops[k] ?? root.ink
            }

            // Cover art, or an accent disc when the player has none
            Rectangle {
                x: root.cx - width / 2
                y: root.cy - height / 2
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

                    Cover {
                        anchors.fill: parent
                        player: rings.player
                    }
                }
            }
        }
    }

    // Two slots: the new cover fades in over the old one, which only drops once covered.
    // While the art is still downloading the url is empty, so the old cover is held
    component Cover: Item {
        id: cover

        property var player: null

        // Black and white along with a B&W, Invertible or bw-mode wallpaper
        property real gray: Accent.mono ? 1 : 0
        Behavior on gray { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

        layer.enabled: gray > 0
        layer.effect: MultiEffect {
            saturation: -cover.gray
        }

        readonly property string raw: player?.trackArtUrl ?? ""
        readonly property string url: Art.local(raw)
        property Image front: picA
        property Image prev: null

        function fadeTo(pic, value) {
            if (pic === front && fade.running && fade.to === value)
                return;
            settle();
            if (pic !== front) {
                pic.opacity = 0;
                pic.z = 1;
                front.z = 0;
                prev = front;
                front = pic;
            }
            fade.target = pic;
            fade.to = value;
            fade.start();
        }

        // Finish a running fade at once, before its slots get reused
        function settle() {
            if (!fade.running)
                return;
            fade.stop();
            fade.target.opacity = fade.to;
            dropPrev();
        }

        function dropPrev() {
            if (prev)
                prev.opacity = 0;
            prev = null;
        }

        function loaded(pic) {
            if (pic.status === Image.Ready && pic !== front && pic.source.toString() === url)
                fadeTo(pic, 1);
        }

        function load() {
            if (!raw)
                return fadeTo(front, 0);
            if (!url)
                return;
            if (front.source.toString() === url && front.status === Image.Ready)
                return fadeTo(front, 1);
            const back = front === picA ? picB : picA;
            if (back.source.toString() === url && back.status === Image.Ready)
                fadeTo(back, 1);
            else {
                if (back === prev)
                    settle();
                back.source = url;
            }
        }

        onRawChanged: Qt.callLater(load)
        onUrlChanged: Qt.callLater(load)
        Component.onCompleted: load()

        NumberAnimation {
            id: fade
            property: "opacity"
            duration: 500
            easing.type: Easing.InOutQuad
            onFinished: cover.dropPrev()
        }

        CoverPic {
            id: picA
            onStatusChanged: cover.loaded(picA)
        }

        CoverPic {
            id: picB
            onStatusChanged: cover.loaded(picB)
        }
    }

    component CoverPic: Image {
        anchors.fill: parent
        opacity: 0
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(512, 512)
        asynchronous: true
    }

    // Particles flying out of the centre, Trap Nation style. They drift at rest and rush outwards on
    // the bass, with kicks as bursts; the speed is integrated here so the motion never jumps.
    // Drawn by particles.frag, in units of the rect's height
    Component {
        id: particles

        ShaderEffect {
            id: field

            // Cells per layer around the circle, matching the shader
            readonly property var sectors: [70, 110, 170]
            // Parallax: nearer layers move faster
            readonly property var rates: [1.4, 1, 0.7]
            property real speed: 0.12
            property vector4d offsets: Qt.vector4d(0, 0, 0, 0)

            readonly property real aspect: width / height
            readonly property real pixel: 1 / height
            readonly property real inner: 0.12
            readonly property real level: Math.min(1, Cava.level * root.gain)
            readonly property point origin: Qt.point(0, 0)
            // Spread 1 matches the old full-screen field, whatever the rect's height
            readonly property real zoom: (root.cfg.spread ?? 1) * root.sh / Math.max(1, height)
            readonly property real density: root.cfg.pDensity ?? 1
            readonly property real dotScale: root.cfg.pSize ?? 1
            readonly property color accent: root.ink
            readonly property color highlight: Theme.text

            fragmentShader: Qt.resolvedUrl("../../shaders/particles.frag.qsb")

            FrameAnimation {
                running: root.active && root.visible
                onTriggered: {
                    const dt = Math.min(frameTime, 0.05);
                    const target = (0.12 + (Cava.bass * 1.1 + Cava.kick * 2.2) * root.gain) * (root.cfg.pSpeed ?? 1);
                    // Fast to speed up, slower to settle back
                    field.speed += (target - field.speed) * Math.min(1, dt * (target > field.speed ? 14 : 3));
                    const o = [field.offsets.x, field.offsets.y, field.offsets.z];
                    // Shift in log radius, in cells; wrapped at the shader's hash period
                    for (let i = 0; i < 3; i++)
                        o[i] = (o[i] + dt * field.speed * field.rates[i] * field.sectors[i] / (Math.PI * 2)) % 4096;
                    field.offsets = Qt.vector4d(o[0], o[1], o[2], 0);
                }
            }
        }
    }
}
