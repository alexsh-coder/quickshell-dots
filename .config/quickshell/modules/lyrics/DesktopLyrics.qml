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
    // Dark-scheme colors in either scheme: the lyrics sit on the wallpaper, not on a themed surface
    // (LyricText repeats the halo, inline components cannot see root)
    readonly property color accent: Accent.base
    readonly property color textColor: "#e6edf3"
    readonly property color halo: "#000000"
    // Playback position, read every frame while playing so the glow follows the vocals smoothly
    property real pos: 0

    visible: active || view.opacity > 0

    WlrLayershell.namespace: "lyrics"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    margins.bottom: Math.round(screen.height * 0.11)
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

        delegate: Item {
            id: line

            required property var modelData
            required property int index

            readonly property int dist: Math.abs(index - view.currentIndex)
            readonly property bool current: dist === 0

            width: view.width
            height: modelData.words ? words.implicitHeight : plain.implicitHeight
            opacity: current ? 1 : dist === 1 ? 0.6 : 0
            scale: current ? 1 : 0.75

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

            Item {
                id: body

                anchors.fill: parent
                layer.enabled: line.opacity > 0
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.halo
                    // Dense halo instead of a drop shadow, so the text holds up on any wallpaper
                    shadowOpacity: 0.85
                    shadowBlur: 0.45
                }

                // Line-synced lyrics: the whole line lights up
                LyricText {
                    id: plain

                    visible: !line.modelData.words
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: line.modelData.text || "♪"
                    color: line.current ? root.accent : root.textColor

                    Behavior on color {
                        ColorAnimation {
                            duration: root.growDuration
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

                    // Centred greedy wrap; breaks after spaces and CJK characters
                    function layout() {
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
                            const shift = (width - (last.x + last.width - row[0].x)) / 2 - row[0].x;
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
                            readonly property real gap: /\s$/.test(modelData.text) ? space.advanceWidth : 0
                            readonly property bool breakable: gap > 0 || /[\u3000-\u9fff\uac00-\ud7af\uff00-\uffef]$/.test(label)
                            // Hold the glow across short gaps up to the next word, so it doesn't flicker
                            readonly property real end: {
                                const next = line.modelData.words[index + 1];
                                const sung = modelData.time + modelData.dur;
                                return Math.min(Math.max(sung, next?.time ?? 0), sung + 0.6);
                            }
                            readonly property bool singing: line.current && root.pos >= modelData.time && root.pos < end
                            property real glow: singing ? 1 : 0
    
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
                                opacity: word.glow
                                visible: opacity > 0

                                Repeater {
                                    model: [8, 16, 32, 48, 64]

                                    LyricText {
                                        id: bloom
                                        required property int modelData
                                        text: word.label
                                        color: root.accent
                                        // Outline in the accent thickens the glyphs, so the wide blurs keep their mass
                                        styleColor: root.accent
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

                                LyricText {
                                    text: word.label
                                    color: root.accent
                                }
                            }

                            LyricText {
                                id: base
                                text: word.label
                                color: line.current ? root.accent : root.textColor

                                Behavior on color {
                                    ColorAnimation {
                                        duration: root.growDuration
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
    }

    TextMetrics {
        id: space
        font: probe.font
        text: " "
    }

    LyricText {
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

    IpcHandler {
        target: "lyrics"

        function toggle(): void {
            MusicFx.lyrics = !MusicFx.lyrics;
        }

        function reload(): void {
            Lyrics.reload();
        }
    }
}
