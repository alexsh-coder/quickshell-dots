import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.config
import qs.components
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
    readonly property color accent: Theme.hueShift((cfg.color ?? "auto") === "auto" ? Accent.base : Theme.paint(cfg.color))
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
        const parts = l.text.match(/\S+\s*/g) ?? [];
        const next = Lyrics.lines[i + 1]?.time ?? l.time + parts.length * 0.4;
        const step = Math.min(0.6, (next - l.time) / Math.max(1, parts.length));
        return { time: l.time, text: l.text, words: parts.map((w, k) => ({ time: l.time + k * step, dur: step, text: w })) };
    })
    // Playback position, read every frame while playing so the glow follows the vocals smoothly
    property real pos: 0

    // Motion of the sung text: shake, extras, and a clock driving them
    readonly property string shake: cfg.shake ?? "off"
    readonly property var textFx: [].concat(cfg.textFx ?? [])
    readonly property bool moving: shake !== "off" || textFx.length > 0
    property real clock: 0
    // Smoothed beat so "beat" shake and pulse don't strobe
    property real beat: 0
    // Tremble: a fresh random target every frame, eased into, the way the ring's text trembles
    property real jx: 0
    property real jy: 0
    property real jr: 0
    readonly property point jolt: {
        const t = clock, a = size;
        // Slow drift; under "beat" it settles as the music hits and the tremble takes over
        const sway = shake === "float" ? 1 : shake === "beat" ? 1 - 0.8 * beat : 0;
        return Qt.point((Math.sin(t * 0.8) * 0.14 + Math.sin(t * 0.37) * 0.06) * a * sway + jx,
                        Math.sin(t * 1.1 + 1) * 0.1 * a * sway + jy);
    }
    readonly property real tilt: textFx.includes("tilt") ? Math.sin(clock * 0.6) * 2.5 : 0
    readonly property real pulse: textFx.includes("pulse") ? 1 + beat * 0.08 : 1
    // Neon flicker: a short dip now and then, more often on loud parts
    property real flicker: 1

    FrameAnimation {
        running: root.visible && (root.active && root.moving || root.showInfo)
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            root.clock = (root.clock + dt) % 3600;
            const target = Math.min(1, Cava.bass * 0.7 + Cava.kick);
            root.beat += (target - root.beat) * Math.min(1, dt * (target > root.beat ? 25 : 6));
            // Jitter trembles all the time; beat only on kicks and the bass, in a tighter range than the sway
            const energy = root.shake === "jitter" ? 0.6 : root.shake === "beat" ? Math.min(1, Cava.kick + Cava.bass * 0.35) : 0;
            const amp = root.size * 0.06 * energy, ease = Math.min(1, dt * 30);
            root.jx += ((Math.random() * 2 - 1) * amp - root.jx) * ease;
            root.jy += ((Math.random() * 2 - 1) * amp - root.jy) * ease;
            root.jr += ((Math.random() * 2 - 1) * 1.5 * energy - root.jr) * ease;
            if (root.textFx.includes("flicker"))
                root.flicker = Math.random() < dt * (0.6 + Cava.kick * 8) ? 0.25 + Math.random() * 0.4 : Math.min(1, root.flicker + dt * 9);
            else
                root.flicker = 1;
        }
    }

    // No lyrics for the track: a "now playing" card instead. A small header (a live equalizer, note or
    // spinning disc, and the label), the title, and the artist under it; or one line taking turns
    readonly property string noLyrics: cfg.noLyrics ?? "none"
    // arc: header, text and the curved bar; minimal: text only; cover: art on the left;
    // marquee: one scrolling line
    readonly property string infoStyle: cfg.infoStyle ?? "arc"
    readonly property int infoAlign: infoStyle === "cover" ? Text.AlignLeft : align
    readonly property real infoSize: size * (cfg.infoScale ?? 1)
    readonly property var info: {
        const p = Lyrics.player;
        if (!p || noLyrics === "none")
            return [];
        const t = p.trackTitle || "", a = p.trackArtist || "", al = p.trackAlbum || "";
        const sub = [a, al].filter(x => x.trim() && x !== t).join("  ·  ");
        if (infoStyle === "marquee")
            return [[t, a].filter(x => x.trim()).join("  —  ")];
        const pick = { full: [t + "\n" + sub], title: [t], swap: [t, a], cycle: [t, a, al] }[noLyrics] ?? [];
        // No repeats: an album named like the track is skipped
        return pick.filter((x, i) => x.trim().length && pick.indexOf(x) === i);
    }
    // Only once the search came back empty, so it doesn't flash while lyrics load
    readonly property bool showInfo: MusicFx.lyrics && Lyrics.lines.length === 0 && (Lyrics.key in Lyrics.cache) && info.length > 0
    property int infoIndex: 0
    onInfoChanged: infoIndex = 0

    // Long names shrink to about the progress arc's width (a little overhang is fine). The lines that
    // take turns, and the title with the line under it, stay within a small size ratio of each other
    readonly property real fitWidth: Math.min(width, infoSize * 10) * 1.12
    readonly property real maxRatio: 1.25
    readonly property var infoFits: {
        const fit = t => infoStyle === "marquee" ? 1 : t.trim() ? Math.max(0.45, Math.min(1, fitWidth / Math.max(1, titleMetrics.advanceWidth(t)))) : 1;
        const out = info.map(x => {
            const parts = x.split("\n");
            const main = fit(parts[0]);
            // The second line is 0.8 of the title; a long one shrinks a bit more, never past 0.72 of it
            const sub = parts[1] ? Math.min(1, fitWidth / Math.max(1, titleMetrics.advanceWidth(parts[1]) * 0.8)) : 1;
            return { main: main, sub: sub };
        });
        // Taking turns: nothing more than the ratio smaller than the biggest
        const top = Math.max(...out.map(o => o.main), 0);
        return out.map(o => {
            const main = Math.max(o.main, top / maxRatio);
            return { main: main, sub: Math.max(main * 0.9, Math.min(o.sub, main)) };
        });
    }

    FontMetrics {
        id: titleMetrics
        font.family: Theme.font
        font.pixelSize: root.infoSize * 1.3
        font.weight: Font.Black
    }

    Timer {
        running: root.showInfo && root.info.length > 1
        repeat: true
        interval: (root.cfg.swapTime ?? 6) * 1000
        onTriggered: root.infoIndex = (root.infoIndex + 1) % root.info.length
    }

    Item {
        id: infoStage

        readonly property string target: root.showInfo ? (root.info[root.infoIndex] ?? "") : ""
        property bool flip: false
        readonly property real slotH: Math.max(infoA.contentH, infoB.contentH)
        readonly property real textW: Math.max(infoA.visible ? infoA.contentW : 0, infoB.visible ? infoB.contentW : 0)
        readonly property real gap: root.infoSize * 0.35

        anchors.fill: parent
        opacity: root.showInfo ? (Lyrics.player?.isPlaying ? 1 : (root.cfg.paused ?? 0.45)) : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim * 2 } }

        onTargetChanged: {
            (flip ? infoB : infoA).fit = root.infoFits[root.infoIndex] ?? { main: 1, sub: 1 };
            (flip ? infoB : infoA).text = target;
            flip = !flip;
        }

        Motion {
            id: cardMotion
            target: infoStage
            lift: root.textFx.includes("wave") ? Math.sin(root.clock * 3.2) * root.size * 0.15 : 0
        }
        transform: cardMotion.list
        layer.enabled: visible && (root.cfg.halo ?? true)
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.halo
            shadowOpacity: 0.85
            shadowBlur: 0.45
        }

        // Header, text and bar. The text sits in the middle of the rect, the header just above it, and the
        // bar under it, pulled up into the arc's dip as far as the text's width lets it
        Item {
            id: card

            readonly property bool cover: root.infoStyle === "cover"
            readonly property bool header: root.infoStyle !== "minimal" && ((root.cfg.infoLabel ?? true) || (root.cfg.infoIcon ?? "eq") !== "none")
            readonly property bool showBar: root.infoStyle !== "minimal" && (root.cfg.infoProgress ?? true)
            readonly property real textY: header ? head.height + infoStage.gap * 0.6 : 0
            readonly property real textBottom: textY + infoStage.slotH
            readonly property real coverSize: cover ? Math.max(root.infoSize * 2.5, textBottom + (showBar ? root.infoSize * 0.9 : 0)) : 0
            readonly property real coverGap: cover ? root.infoSize * 0.6 : 0

            width: cover ? Math.min(parent.width, coverSize + coverGap + root.fitWidth / 1.12) : parent.width
            height: Math.max(textBottom, showBar ? bar.y + bar.height : 0, coverSize)
            x: !cover || root.infoAlign === Text.AlignHCenter ? (parent.width - width) / 2 : root.infoAlign === Text.AlignRight ? parent.width - width : 0
            y: cover ? (parent.height - height) / 2 : parent.height / 2 - (textY + infoStage.slotH / 2)
            opacity: root.flicker

            Rectangle {
                visible: card.cover
                width: card.coverSize
                height: width
                y: (card.height - height) / 2
                radius: root.infoSize * 0.35
                color: Qt.alpha(root.textColor, 0.12)
                layer.enabled: card.cover
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: coverMask
                }

                Image {
                    anchors.fill: parent
                    source: card.cover ? (Lyrics.player?.trackArtUrl ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(256, 256)
                    asynchronous: true
                }
            }

            Rectangle {
                id: coverMask
                visible: false
                layer.enabled: true
                width: card.coverSize
                height: width
                radius: root.infoSize * 0.35
            }

            Item {
                id: content

                x: card.coverSize + card.coverGap
                width: card.width - x
                height: card.height
                y: card.cover ? (card.height - Math.max(card.textBottom, card.showBar ? bar.y + bar.height : 0)) / 2 : 0

            Row {
                id: head

                visible: card.header
                spacing: root.infoSize * 0.3
                height: root.infoSize * 0.55
                x: root.infoAlign === Text.AlignLeft ? 0 : root.infoAlign === Text.AlignRight ? parent.width - width : (parent.width - width) / 2

                // Live equalizer: four little bars from the spectrum
                Row {
                    visible: (root.cfg.infoIcon ?? "eq") === "eq"
                    anchors.verticalCenter: parent.verticalCenter
                    height: head.height
                    spacing: Math.max(1.5, head.height * 0.14)

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            readonly property real v: Math.min(1, (Cava.values[[2, 8, 16, 28][index]] ?? 0) * 1.3)

                            anchors.bottom: parent.bottom
                            width: Math.max(2, head.height * 0.16)
                            height: head.height * (0.2 + 0.8 * (Lyrics.player?.isPlaying ? v : 0.1))
                            radius: width / 2
                            color: root.accent
                            Behavior on height { NumberAnimation { duration: 70 } }
                        }
                    }
                }

                Icon {
                    visible: ["note", "disc"].includes(root.cfg.infoIcon)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cfg.infoIcon === "disc" ? "album" : "music_note"
                    font.pixelSize: head.height * 1.25
                    color: root.accent
                    // The disc spins, the note nods on the beat
                    rotation: root.cfg.infoIcon === "disc" ? discSpin.angle : -8 * root.beat
                    scale: root.cfg.infoIcon === "note" ? 1 + root.beat * 0.2 : 1

                    FrameAnimation {
                        id: discSpin
                        property real angle: 0
                        running: root.showInfo && root.cfg.infoIcon === "disc" && (Lyrics.player?.isPlaying ?? false)
                        onTriggered: angle = (angle + frameTime * 120) % 360
                    }
                }

                Text {
                    visible: root.cfg.infoLabel ?? true
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lyrics.player?.isPlaying ? "NOW PLAYING" : "PAUSED"
                    font.family: Theme.font
                    font.pixelSize: head.height * 0.8
                    font.weight: Font.DemiBold
                    font.letterSpacing: head.height * 0.25
                    color: root.accent
                    opacity: 0.85
                }
            }

            Item {
                y: card.textY
                width: parent.width
                height: infoStage.slotH

                InfoSlot { id: infoA; on: infoStage.flip }
                InfoSlot { id: infoB; on: !infoStage.flip }
            }

            // Track progress under it all: a round-capped line whose played part ripples with the music,
            // like Android's squiggly media bar, and a dot at the playhead
            Shape {
                id: bar

                readonly property real thick: Math.max(3, root.infoSize * 0.13)
                readonly property real amp: Math.max(1.5, root.infoSize * 0.12)
                readonly property real done: Math.max(0, Math.min(1, root.pos / Math.max(1, Lyrics.player?.length ?? 1)))
                // Bent along a slice of an ellipse: smile dips in the middle, arch bows up
                readonly property string arc: root.infoStyle === "arc" ? (root.cfg.infoArc ?? "smile") : "flat"
                readonly property real bend: arc === "flat" ? 0 : root.infoSize * 0.9 * (arc === "arch" ? -1 : 1)
                readonly property real pad: thick + amp
                readonly property real baseY: pad + Math.max(0, -bend)
                readonly property real headU: done
                // Ripple height eased from the level, flat while paused
                property real swell: 0
                property real phase: 0
                property var wave: []
                property var rest: []

                // Point and normal on the curve at u in 0..1
                function at(u) {
                    const k = 0.85, x = 2 * u - 1;
                    const base = Math.sqrt(1 - k * k);
                    const e = (Math.sqrt(1 - k * k * x * x) - base) / (1 - base);
                    const de = -k * k * x / Math.sqrt(1 - k * k * x * x) / (1 - base) * 2;
                    const span = width - thick;
                    const px = thick / 2 + u * span, py = baseY + e * bend;
                    const dx = span, dy = de * bend, l = Math.hypot(dx, dy);
                    return { x: px, y: py, nx: -dy / l, ny: dx / l };
                }

                // Highest point of the curve under the text, in this shape's coordinates; the text has to stay above it
                function clearance(tw) {
                    const span = Math.max(1, width - thick), f = Math.min(1, tw / span);
                    const lo = root.infoAlign === Text.AlignLeft ? 0 : root.infoAlign === Text.AlignRight ? 1 - f : 0.5 - f / 2;
                    let m = Infinity;
                    for (let i = 0; i <= 16; i++)
                        m = Math.min(m, at(lo + f * i / 16).y);
                    return m - thick / 2 - amp;
                }

                visible: card.showBar
                // Sized for the widest text the card allows, so it never moves when the text changes
                y: card.textBottom + root.infoSize * 0.15 - Math.max(0, clearance(root.fitWidth))
                width: Math.min(parent.width, root.infoSize * 10)
                height: pad * 2 + Math.abs(bend)
                x: root.infoAlign === Text.AlignLeft ? 0 : root.infoAlign === Text.AlignRight ? parent.width - width : (parent.width - width) / 2
                preferredRendererType: Shape.CurveRenderer

                FrameAnimation {
                    running: bar.visible && root.showInfo
                    onTriggered: {
                        const dt = Math.min(frameTime, 0.05);
                        const target = Lyrics.player?.isPlaying ? Math.min(1, 0.35 + Cava.level * 0.9 + Cava.kick * 0.4) : 0;
                        bar.swell += (target - bar.swell) * Math.min(1, dt * 8);
                        bar.phase = (bar.phase + dt * (3 + Cava.bass * 6)) % (Math.PI * 2);
                        const span = bar.width - bar.thick, wl = bar.thick * 6, gapU = bar.thick * 1.2 / Math.max(1, span);
                        const w = [], r = [];
                        const n1 = Math.max(2, Math.ceil(bar.headU * span / 3));
                        for (let i = 0; i <= n1; i++) {
                            const u = bar.headU * i / n1, p = bar.at(u);
                            // Settles flat just before the playhead
                            const tail = Math.min(1, (bar.headU - u) * span / (bar.thick * 2));
                            const o = Math.sin(u * span / wl * Math.PI * 2 - bar.phase) * bar.amp * bar.swell * tail;
                            w.push(Qt.point(p.x + p.nx * o, p.y + p.ny * o));
                        }
                        const u0 = Math.min(1, bar.headU + gapU), n2 = Math.max(2, Math.ceil((1 - u0) * span / 6));
                        for (let i = 0; i <= n2; i++) {
                            const p = bar.at(u0 + (1 - u0) * i / n2);
                            r.push(Qt.point(p.x, p.y));
                        }
                        bar.wave = w;
                        bar.rest = u0 < 1 ? r : [];
                    }
                }

                ShapePath {
                    strokeWidth: bar.thick
                    strokeColor: bar.rest.length ? Qt.alpha(root.textColor, 0.22) : "transparent"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: bar.rest.length ? bar.rest : [Qt.point(0, 0), Qt.point(0, 0)] }
                }
                ShapePath {
                    strokeWidth: bar.thick
                    strokeColor: bar.wave.length ? root.accent : "transparent"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: bar.wave.length ? bar.wave : [Qt.point(0, 0), Qt.point(0, 0)] }
                }

                Rectangle {
                    readonly property var p: bar.at(bar.headU)
                    width: bar.thick * 2.2
                    height: width
                    radius: width / 2
                    x: p.x - width / 2
                    y: p.y - height / 2
                    color: root.accent
                    scale: 1 + root.beat * 0.25
                }
            }
            }
        }
    }

    component InfoSlot: Item {
        id: islot

        property bool on
        property string text
        property var fit: ({ main: 1, sub: 1 })
        property real t: on ? 1 : 0
        readonly property string anim: root.cfg.swapAnim ?? "fade"
        readonly property var parts: text.split("\n")
        readonly property real contentH: col.implicitHeight
        readonly property real contentW: Math.min(width, Math.max(mainT.implicitWidth, subT.visible ? subT.implicitWidth : 0))
        // Marquee: a line too long to fit scrolls by, with a copy following it round
        readonly property bool scrolls: root.infoStyle === "marquee" && mainT.implicitWidth > width
        readonly property real loop: mainT.implicitWidth + root.infoSize * 3
        property real scrollX: 0

        FrameAnimation {
            running: islot.scrolls && islot.visible && (Lyrics.player?.isPlaying ?? false)
            onTriggered: islot.scrollX = (islot.scrollX + Math.min(frameTime, 0.05) * root.infoSize * 2.2) % islot.loop
        }
        onTextChanged: scrollX = 0

        Behavior on t { NumberAnimation { duration: root.cfg.swapSpeed ?? 600; easing.type: Easing.OutCubic } }

        width: parent.width
        height: parent.height
        visible: t > 0 && text.length > 0
        opacity: anim === "fade" ? Math.max(0, 2 * t - 1) : t
        x: anim === "slide" ? (1 - t) * width * 0.15 * (on ? 1 : -1) : 0
        y: anim === "rise" ? (1 - t) * root.infoSize * (on ? 1 : -1) : 0
        scale: anim === "zoom" ? (on ? 0.85 + 0.15 * t : 1 + 0.2 * (1 - t)) : 1
        layer.enabled: anim === "blur" && t < 1
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 40
            blur: 1 - islot.t
        }

        Column {
            id: col

            width: parent.width
            spacing: root.infoSize * 0.08

            Item {
                width: parent.width
                height: mainT.implicitHeight
                clip: islot.scrolls

                LyricText {
                    id: mainT
                    width: islot.scrolls ? implicitWidth : parent.width
                    x: islot.scrolls ? -islot.scrollX : 0
                    horizontalAlignment: root.infoAlign
                    elide: islot.scrolls || root.infoStyle === "marquee" ? Text.ElideNone : Text.ElideRight
                    font.pixelSize: root.infoSize * 1.3 * islot.fit.main
                    font.weight: Font.Black
                    text: islot.parts[0] ?? ""
                    color: root.textColor
                }
                LyricText {
                    visible: islot.scrolls
                    x: mainT.x + islot.loop
                    font: mainT.font
                    text: mainT.text
                    color: root.textColor
                }
            }
            LyricText {
                id: subT
                visible: islot.parts.length > 1
                width: parent.width
                horizontalAlignment: root.infoAlign
                elide: Text.ElideRight
                font.pixelSize: root.infoSize * 1.3 * 0.8 * islot.fit.sub
                font.weight: Font.Medium
                style: Text.Normal
                text: islot.parts[1] ?? ""
                color: Qt.alpha(root.textColor, 0.75)
            }
        }
    }

    // Shake, tilt and pulse around an item's centre
    component Motion: Item {
        id: motion
        property Item target
        property real extra: 1
        property real lift: 0
        Translate { id: mt; x: root.jolt.x; y: root.jolt.y + motion.lift }
        Rotation { id: mr; origin.x: motion.target.width / 2; origin.y: motion.target.height / 2; angle: root.tilt + root.jr }
        Scale { id: ms; origin.x: motion.target.width / 2; origin.y: motion.target.height / 2; xScale: root.pulse * motion.extra; yScale: xScale }
        readonly property var list: [ms, mr, mt]
    }

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

        Motion { id: viewMotion; target: view }
        transform: viewMotion.list

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

        Motion { id: stageMotion; target: stage }
        transform: stageMotion.list

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
        // fade: out then in, the two lines never share the screen
        opacity: anim === "fade" ? Math.max(0, 2 * t - 1) : t
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

        // Start of the word on screen and of whatever replaces it, for the drift
        readonly property var span: {
            const parts = target.split(":");
            const l = root.timed[+parts[0]], k = +parts[1];
            const w = l?.words[k];
            if (!w)
                return [0, 1];
            return [w.time, l.words[k + 1]?.time ?? root.timed[+parts[0] + 1]?.time ?? w.time + w.dur + 1.5];
        }
        readonly property real drift: {
            const mode = root.cfg.drift ?? "off";
            if (mode === "off" || !single)
                return 1;
            const f = Math.max(0, Math.min(1, (root.pos - span[0]) / Math.max(0.2, span[1] - span[0])));
            return 1 + (mode === "grow" ? 0.07 : -0.07) * f;
        }
        readonly property bool single: root.single

        onTargetChanged: {
            const text = target.split(":").slice(2).join(":");
            // The leaving word keeps the size it drifted to
            (flip ? slotA : slotB).held = drift;
            (flip ? slotB : slotA).text = text;
            flip = !flip;
        }

        WordSlot { id: slotA; on: one.flip }
        WordSlot { id: slotB; on: !one.flip }
    }

    component WordSlot: Text {
        id: slot

        property bool on
        property real held: 1
        property real t: on ? 1 : 0
        readonly property string anim: root.cfg.wordAnim ?? "rise"
        readonly property real travel: font.pixelSize * 0.5

        Behavior on t { NumberAnimation { duration: root.cfg.wordTime ?? 320; easing.type: Easing.OutCubic } }

        x: root.align === Text.AlignLeft ? 0 : root.align === Text.AlignRight ? parent.width - width : (parent.width - width) / 2
        y: (parent.height - height) / 2 + (anim === "rise" ? (1 - t) * travel * (on ? 1 : -1) : 0)
        opacity: (anim === "fade" ? Math.max(0, 2 * t - 1) : t) * (on ? root.flicker : 1)
        scale: anim === "pop" ? (on ? 0.6 + 0.4 * t : 1 + 0.4 * (1 - t)) : 1
        visible: t > 0
        Motion {
            id: wordMotion
            target: slot
            extra: slot.on ? one.drift : slot.held
            lift: root.textFx.includes("wave") ? Math.sin(root.clock * 3.2) * slot.travel * 0.3 : 0
        }
        transform: wordMotion.list
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

        // Shrinks or grows a little through the line, held where it ended once it's sung
        readonly property real drift: {
            const mode = host.cfg.drift ?? "off";
            if (mode === "off" || (!current && !past))
                return 1;
            let f = 1;
            if (current) {
                const next = host.timed[index + 1]?.time ?? modelData.time + 5;
                f = Math.max(0, Math.min(1, (host.pos - modelData.time) / Math.max(0.5, next - modelData.time)));
            }
            return 1 + (mode === "grow" ? 0.07 : -0.07) * f;
        }

        // Shake and the rest move the whole block (see viewMotion), so nothing jumps when lines change
        transform: [stillScale]
        Scale { id: stillScale; origin.x: line.width / 2; origin.y: line.height / 2; xScale: line.drift; yScale: xScale }

        width: parent?.width ?? 0
        height: modelData.words ? words.implicitHeight : plain.implicitHeight
        opacity: (current ? host.flicker : 1) * (current ? 1 : dist <= host.context ? Math.pow(host.cfg.fade ?? 0.6, dist) : 0)
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
                            Translate { y: (host.has("lift") ? -host.size * 0.18 * word.glow : 0) + (host.textFx.includes("wave") && line.current ? Math.sin(host.clock * 3.2 - word.index * 0.7) * host.size * 0.12 : 0) }
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
        running: (root.active || root.showInfo) && root.visible && (Lyrics.player?.isPlaying ?? false)
        onTriggered: root.pos = Lyrics.player.position
    }

    Connections {
        target: Lyrics.player
        function onPositionChanged() {
            root.pos = Lyrics.player.position;
        }
    }
}
