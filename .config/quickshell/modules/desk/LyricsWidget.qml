import QtQuick
import QtQuick.Effects
import qs.config
import qs.services

// Synced lyrics as a desktop widget (see Desk): the current line with its neighbours, word by word
// where the lyrics have timings. Hidden while the lyrics switch is off or the track has none
Item {
    id: root

    property var cfg: ({})
    readonly property bool active: MusicFx.lyrics && Lyrics.lines.length > 0
    readonly property int moveDuration: 600
    readonly property int growDuration: 450
    readonly property real size: cfg.size ?? 22
    readonly property int context: cfg.context ?? 1
    readonly property int align: ({ left: Text.AlignLeft, right: Text.AlignRight })[cfg.align] ?? Text.AlignHCenter
    // Sung line and the rest; "auto" keeps the old look: the wallpaper's accent on light text
    readonly property color accent: (cfg.color ?? "auto") === "auto" ? Accent.base : Theme.paint(cfg.color)
    readonly property color textColor: ({ white: "#e6edf3", black: "#1f2328", accent: Accent.color })[cfg.text] ?? "#e6edf3"
    readonly property color halo: textColor.hslLightness > 0.5 ? "#000000" : "#ffffff"
    // Sung-word effects, any mix of them (an old single choice reads as a list of one)
    readonly property var effects: [].concat(cfg.effect ?? ["glow"])
    function has(name) {
        return effects.includes(name);
    }
    readonly property bool single: cfg.layout === "word"
    readonly property real spaceW: space.advanceWidth
    readonly property string lineAnim: cfg.lineAnim ?? "scroll"
    // Every line timed word by word: lines without word timings get theirs spread evenly over the line
    readonly property var timed: Lyrics.lines.map((l, i) => {
        if (l.words?.length)
            return l;
        const parts = l.text.split(/(?<=\s)/).filter(w => w.trim());
        const next = Lyrics.lines[i + 1]?.time ?? l.time + parts.length * 0.4;
        const step = Math.min(0.6, (next - l.time) / Math.max(1, parts.length));
        return { time: l.time, text: l.text, words: parts.map((w, k) => ({ time: l.time + k * step, dur: step, text: w })) };
    })
    // Playback position, read every frame while playing so the glow follows the vocals smoothly
    property real pos: 0

    ListView {
        id: view

        anchors.fill: parent
        model: root.active ? root.timed : []
        visible: !root.single && root.lineAnim === "scroll"
        currentIndex: Lyrics.index
        interactive: false
        spacing: root.size * 0.2

        // Scroll by animating a hidden highlight, so the list glides on a custom
        // curve instead of ListView's built-in SmoothedAnimation
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (height - root.size * 1.45) / 2
        preferredHighlightEnd: (height + root.size * 1.45) / 2
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

        opacity: root.active ? (Lyrics.player?.isPlaying ? 1 : (root.cfg.paused ?? 0.45)) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

        delegate: Line {
            host: root
            width: view.width
            dist: Math.abs(index - view.currentIndex)
            past: index < view.currentIndex
        }
    }

    // Lines that swap instead of scrolling: the old one leaves as the new one comes in
    Item {
        id: stage

        readonly property int target: root.active && !root.single && root.lineAnim !== "scroll" ? Lyrics.index : -1
        property bool flip: false

        anchors.fill: parent
        visible: !root.single && root.lineAnim !== "scroll"
        opacity: root.active ? (Lyrics.player?.isPlaying ? 1 : (root.cfg.paused ?? 0.45)) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

        onTargetChanged: {
            (flip ? slotLineB : slotLineA).which = target;
            flip = !flip;
        }

        LineSlot { id: slotLineA; on: stage.flip }
        LineSlot { id: slotLineB; on: !stage.flip }
    }

    component LineSlot: Item {
        id: lslot

        property bool on
        property int which: -1
        property real t: on ? 1 : 0
        readonly property string anim: root.lineAnim

        Behavior on t { NumberAnimation { duration: root.cfg.lineTime ?? 450; easing.type: Easing.OutCubic } }

        width: parent.width
        height: parent.height
        visible: t > 0 && which >= 0
        opacity: t
        x: anim === "slide" ? (1 - t) * width * 0.2 * (on ? 1 : -1) : 0
        y: anim === "rise" ? (1 - t) * root.size * 2 * (on ? 1 : -1) : 0
        scale: anim === "zoom" ? (on ? 0.8 + 0.2 * t : 1 + 0.25 * (1 - t)) : 1
        layer.enabled: anim === "blur" && t < 1
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 40
            blur: 1 - lslot.t
        }

        Line {
            host: root
            width: parent.width
            y: (parent.height - height) / 2
            modelData: root.timed[lslot.which] ?? { time: 0, text: "", words: [] }
            index: lslot.which
            dist: lslot.on ? 0 : 1
            past: !lslot.on
            opacity: 1
            scale: 1
        }
    }

    // One word at a time, big, swapping with an animation
    Item {
        id: one

        readonly property string target: {
            if (!root.single || !root.active)
                return "";
            const l = root.timed[Lyrics.index], t = root.pos;
            if (!l)
                return "";
            let w = null, k = -1;
            l.words.forEach((x, j) => {
                if (x.time <= t) {
                    w = x;
                    k = j;
                }
            });
            // Gone during long gaps
            const next = l.words[k + 1]?.time ?? root.timed[Lyrics.index + 1]?.time ?? Infinity;
            if (!w || t > Math.min(next, w.time + w.dur + 1.5))
                return "";
            let s = (root.cfg.punct ?? false) ? w.text.trim() : w.text.trim().replace(/[,.;:!?…"“”«»()]+/g, "");
            s = root.cfg.wordCase === "upper" ? s.toUpperCase() : root.cfg.wordCase === "lower" ? s.toLowerCase() : s;
            return Lyrics.index + ":" + k + ":" + s;
        }
        property bool flip: false

        anchors.fill: parent
        visible: root.single
        opacity: root.active ? (Lyrics.player?.isPlaying ? 1 : (root.cfg.paused ?? 0.45)) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

        onTargetChanged: {
            const text = target.split(":").slice(2).join(":");
            (flip ? slotB : slotA).text = text;
            flip = !flip;
        }

        WordSlot { id: slotA; on: one.flip }
        WordSlot { id: slotB; on: !one.flip }
    }

    component WordSlot: Text {
        id: slot

        property bool on
        property real t: on ? 1 : 0
        readonly property string anim: root.cfg.wordAnim ?? "rise"
        readonly property real travel: font.pixelSize * 0.5

        Behavior on t { NumberAnimation { duration: root.cfg.wordTime ?? 320; easing.type: Easing.OutCubic } }

        x: root.align === Text.AlignLeft ? 0 : root.align === Text.AlignRight ? parent.width - width : (parent.width - width) / 2
        y: (parent.height - height) / 2 + (anim === "rise" ? (1 - t) * travel * (on ? 1 : -1) : 0)
        opacity: t
        scale: anim === "pop" ? (on ? 0.6 + 0.4 * t : 1 + 0.4 * (1 - t)) : 1
        visible: t > 0
        font.family: Theme.font
        font.pixelSize: root.size * (root.cfg.wordScale ?? 2.5)
        font.weight: Font.Black
        color: root.accent
        style: Text.Outline
        styleColor: Qt.alpha("#000000", 0.5)
        layer.enabled: anim === "blur" && t < 1 || (root.cfg.halo ?? true)
        layer.effect: MultiEffect {
            blurEnabled: slot.anim === "blur"
            blurMax: 48
            blur: 1 - slot.t
            shadowEnabled: root.cfg.halo ?? true
            shadowColor: root.halo
            shadowOpacity: 0.8
            shadowBlur: 0.5
        }
    }

    // One lyric line, word by word; `dist` is how far it is from the sung line
    component Line: Item {
        required property Item host
        id: line

        required property var modelData
        required property int index

        property int dist: 0
        // Already sung: stays in the accent while it fades, never back to the plain color
        property bool past: false
        readonly property bool current: dist === 0
        readonly property bool lit: current || past

        width: parent?.width ?? 0
        height: modelData.words ? words.implicitHeight : plain.implicitHeight
        opacity: current ? 1 : dist <= host.context ? Math.pow(host.cfg.fade ?? 0.6, dist) : 0
        scale: current ? 1 : host.cfg.shrink ?? 0.75

        Behavior on scale {
            NumberAnimation {
                duration: host.growDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.emphasizedDecel
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: host.growDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.emphasizedDecel
            }
        }

        Item {
            id: body

            anchors.fill: parent
            layer.enabled: line.opacity > 0 && (host.cfg.halo ?? true)
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: host.halo
                // Dense halo instead of a drop shadow, so the text holds up on any wallpaper
                shadowOpacity: 0.85
                shadowBlur: 0.45
            }

            // Line-synced lyrics: the whole line lights up
            LyricText {
                font.pixelSize: host.size
                id: plain

                visible: !line.modelData.words
                width: parent.width
                horizontalAlignment: host.align
                wrapMode: Text.WordWrap
                text: line.modelData.text || "♪"
                color: line.lit ? host.accent : host.textColor

                Behavior on color {
                    ColorAnimation {
                        duration: host.growDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.emphasizedDecel
                    }
                }
            }

            // Word-synced lyrics: the line lights up like a plain one, and the word being sung glows
            Item {
                id: words

                visible: !!line.modelData.words
                width: parent.width
                onWidthChanged: Qt.callLater(layout)

                Connections {
                    target: root
                    function onAlignChanged() { Qt.callLater(words.layout); }
                }

                // Bounce: a dot hops from word to word, landing on each as it starts
                readonly property var ball: {
                    if (!host.has("bounce") || !line.current)
                        return null;
                    const ws = line.modelData.words ?? [], t = host.pos;
                    let i = 0;
                    while (i + 1 < ws.length && ws[i + 1].time <= t)
                        i++;
                    const a = wordRepeater.itemAt(i), b = wordRepeater.itemAt(i + 1);
                    if (!a)
                        return null;
                    // Rests on a word, then hops so it lands just ahead of the next one starting:
                    // the eye reads the landing as the beat, and arriving late looks lagging
                    let f = 0;
                    if (b) {
                        const next = ws[i + 1].time - 0.06;
                        const hop = Math.min(0.38, (ws[i + 1].time - ws[i].time) * 0.85);
                        f = Math.max(0, Math.min(1, (t - (next - hop)) / hop));
                    }
                    const ax = a.x + a.width / 2, bx = b ? b.x + b.width / 2 : ax;
                    const ay = a.y, by = b ? b.y : ay;
                    return { x: ax + (bx - ax) * f, y: ay + (by - ay) * f - Math.sin(Math.PI * f) * host.size * 0.7 };
                }

                Rectangle {
                    z: 2
                    visible: !!words.ball
                    width: host.size * 0.3
                    height: width
                    radius: width / 2
                    color: host.accent
                    x: (words.ball?.x ?? 0) - width / 2
                    y: (words.ball?.y ?? 0) - height - host.size * 0.12
                }

                // Centred greedy wrap; breaks after spaces and CJK characters
                function layout() {
                    if (!host)
                        return;
                    const items = [];
                    for (let i = 0; i < wordRepeater.count; i++)
                    items.push(wordRepeater.itemAt(i));
                    if (!items.length || items.some(w => !w))
                    return;
                    const rowH = items[0].height;
                    const rows = [[]];
                    let x = 0;
                    let unit = [];
                    let unitW = 0;
                    const flush = () => {
                        const row = rows[rows.length - 1];
                        const gap = row.length ? row[row.length - 1].gap : 0;
                        if (row.length && x + gap + unitW > width) {
                            rows.push([]);
                            x = 0;
                        } else {
                            x += gap;
                        }
                        for (const w of unit) {
                            w.x = x;
                            w.y = (rows.length - 1) * rowH;
                            x += w.width + (w === unit[unit.length - 1] ? 0 : w.gap);
                            rows[rows.length - 1].push(w);
                        }
                        unit = [];
                        unitW = 0;
                    };
                    for (const w of items) {
                        unitW += (unit.length ? unit[unit.length - 1].gap : 0) + w.width;
                        unit.push(w);
                        if (w.breakable)
                        flush();
                    }
                    if (unit.length)
                    flush();
                    for (const row of rows) {
                        if (!row.length)
                        continue;
                        const last = row[row.length - 1];
                        const free = width - (last.x + last.width - row[0].x);
                        const shift = (host.align === Text.AlignLeft ? 0 : host.align === Text.AlignRight ? free : free / 2) - row[0].x;
                        for (const w of row)
                        w.x += shift;
                    }
                    implicitHeight = rows.length * rowH;
                }

                Repeater {
                    id: wordRepeater

                    model: line.modelData.words ?? []

                    Item {
                        id: word

                        required property var modelData
                        required property int index

                        readonly property string label: modelData.text.trim()
                        readonly property real gap: /\s$/.test(modelData.text) ? host.spaceW : 0
                        readonly property bool breakable: gap > 0 || /[\u3000-\u9fff\uac00-\ud7af\uff00-\uffef]$/.test(label)
                        // Hold the glow across short gaps up to the next word, so it doesn't flicker
                        readonly property real end: {
                            const next = line.modelData.words[index + 1];
                            const sung = modelData.time + modelData.dur;
                            return Math.min(Math.max(sung, next?.time ?? 0), sung + 0.6);
                        }
                        readonly property bool singing: line.current && host.pos >= modelData.time && host.pos < end
                        property real glow: singing ? 1 : 0
                        // How far through the word the singing is, 0..1, held at 1 once sung
                        readonly property real progress: !line.current ? (line.past ? 1 : 0) : Math.max(0, Math.min(1, (host.pos - modelData.time) / Math.max(0.05, modelData.dur)))

                        transform: [
                            Scale {
                                origin.x: word.width / 2
                                origin.y: word.height
                                xScale: host.has("lift") ? 1 + 0.12 * word.glow : 1
                                yScale: xScale
                            },
                            Translate { y: host.has("lift") ? -host.size * 0.18 * word.glow : 0 }
                        ]

                        width: base.implicitWidth
                        height: base.implicitHeight
                        onWidthChanged: Qt.callLater(words.layout)

                        Behavior on glow {
                            NumberAnimation {
                                duration: word.singing ? 160 : 700
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Neon glow like stacked CSS text-shadows: several fixed blurs of
                        // growing radius plus a crisp copy on top; only opacity is animated
                        Item {
                            parent: glowPlane
                            x: word.x
                            y: word.y
                            width: word.width
                            height: word.height
                            opacity: host.has("glow") ? word.glow : 0
                            visible: opacity > 0

                            // Built only for the sung line: five blur layers per word are costly to create
                            Loader {
                                active: host.has("glow") && line.current
                                asynchronous: true
                                sourceComponent: Repeater {
                                model: [8, 16, 32, 48, 64]

                                LyricText {
                                    font.pixelSize: host.size
                                    id: bloom
                                    required property int modelData
                                    text: word.label
                                    color: host.accent
                                    // Outline in the accent thickens the glyphs, so the wide blurs keep their mass
                                    styleColor: host.accent
                                    // Soft near the letters, full strength in the wide halo
                                    opacity: modelData >= 32 ? 1 : 0.5
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        blurEnabled: true
                                        blur: 1
                                        blurMax: bloom.modelData
                                    }
                                }
                                }
                            }

                            LyricText {
                                font.pixelSize: host.size
                                text: word.label
                                color: host.accent
                            }
                        }

                        // Fill: the accent sweeps through the word as it's sung, karaoke style
                        Item {
                            z: 1
                            visible: host.has("fill")
                            width: word.width * word.progress
                            height: word.height
                            clip: true

                            LyricText {
                                font.pixelSize: host.size
                                text: word.label
                                color: host.accent
                            }
                        }

                        // Spot: the sung word turns accent at once, an overlay so no slow color fade lags behind
                        LyricText {
                            z: 1
                            visible: host.has("spot") && opacity > 0
                            opacity: word.glow
                            font.pixelSize: host.size
                            text: word.label
                            color: host.accent
                        }

                        Rectangle {
                            visible: host.has("underline")
                            y: word.height - height / 2
                            x: word.width * (1 - word.glow) / 2
                            width: word.width * word.glow
                            height: Math.max(2, host.size * 0.09)
                            radius: height / 2
                            color: host.accent
                        }

                        LyricText {
                            font.pixelSize: host.size
                            id: base
                            text: word.label
                            color: line.lit ? host.accent : host.textColor
                            // Fill: the unsung part is a see-through accent the fill runs over
                            opacity: !line.current ? 1 : host.has("spot") ? 0.25 + 0.75 * word.glow : host.has("fill") ? 0.3 : 1
                            Behavior on opacity { NumberAnimation { duration: 180 } }

                            Behavior on color {
                                ColorAnimation {
                                    duration: host.growDuration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.emphasizedDecel
                                }
                            }
                        }
                    }
                }
            }
        }

        // Above the halo, so the glow isn't darkened by it
        Item {
            id: glowPlane
            anchors.fill: parent
        }
    }

    TextMetrics {
        id: space
        font: probe.font
        text: " "
    }

    LyricText {
        font.pixelSize: root.size
        id: probe
        visible: false
    }

    component LyricText: Text {
        font.family: Theme.font
        font.pixelSize: 22
        font.weight: Font.Bold
        // Subtitle-style crisp edge under the halo
        style: Text.Outline
        styleColor: Qt.alpha("#000000", 0.7)
    }

    FrameAnimation {
        running: root.active && (Lyrics.player?.isPlaying ?? false)
        onTriggered: root.pos = Lyrics.player.position
    }

    Connections {
        target: Lyrics.player
        function onPositionChanged() {
            root.pos = Lyrics.player.position;
        }
    }
}
