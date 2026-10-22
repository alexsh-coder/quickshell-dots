import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config
import qs.components
import qs.services

// Writes lyrics for the playing track and syncs them by tapping along: Space marks
// the highlighted word (or line) at the current playback position. Saved through
// scripts/lyrics-edit.py to ~/.local/share/lyrics, where the desktop lyrics find it.
// Unsaved work stays here per track until it is saved or reverted
Item {
    id: root

    property MprisPlayer player
    property bool active: false
    signal back

    readonly property string script: Quickshell.shellDir + "/scripts/lyrics-edit.py"
    readonly property string key: player ? [player.trackArtist, player.trackTitle].join("\n") : ""
    property var drafts: ({})
    readonly property var doc: drafts[key] ?? null
    // Bumped on every in-place change to doc, so bindings re-read it
    property int rev: 0
    property string tab: "sync"
    property bool lineMode: false
    property real now: 0
    // The word the existing timing says is being sung, to compare against while redoing
    property int playing: -1
    readonly property bool loading: active && !!key && !doc

    readonly property int cursorLine: {
        rev;
        if (!doc || !doc.lines.length)
            return -1;
        const li = lineMode ? doc.lineCursor : doc.cursor < doc.flat.length ? doc.flat[doc.cursor].li : doc.lines.length;
        return Math.min(li, doc.lines.length - 1);
    }
    readonly property var stats: {
        rev;
        if (!doc)
            return { words: 0, lines: 0 };
        return {
            words: doc.flat.filter(f => doc.lines[f.li].words[f.wi].time !== null).length,
            lines: doc.lines.filter(l => lineTime(l) !== null).length
        };
    }

    implicitHeight: column.implicitHeight

    onActiveChanged: {
        if (active)
            open();
        else if (tab === "text")
            applyText();
    }
    onKeyChanged: if (active) open()

    function open() {
        if (!key)
            return;
        if (!doc) {
            load();
            return;
        }
        if (tab === "text")
            edit.text = plainText();
        resync(player.position);
        Qt.callLater(focusIn);
    }

    function focusIn() {
        if (tab === "text")
            edit.forceActiveFocus();
        else
            root.forceActiveFocus();
    }

    function load() {
        const p = player;
        loader.reqKey = key;
        loader.meta = { artist: p.trackArtist, title: p.trackTitle, album: p.trackAlbum, duration: p.length };
        loader.exec(["python3", script, "load", p.trackArtist, p.trackTitle, p.trackAlbum, String(p.length)]);
    }

    function words(l) {
        if (l.words)
            return l.words.filter(w => w.text.trim()).map(w => ({ text: w.text, time: w.time, fresh: false }));
        return (l.text.match(/\S+\s*/g) ?? []).map(t => ({ text: t, time: null, fresh: false }));
    }

    function reindex(d) {
        d.flat = [];
        d.lines.forEach((l, li) => {
            l.base = d.flat.length;
            l.words.forEach((w, wi) => d.flat.push({ li: li, wi: wi }));
        });
    }

    // Every change saves the state before it, so Backspace undoes taps, nudges and deletions alike
    function remember() {
        doc.history.push(JSON.stringify({
            lines: doc.lines.map(l => ({ text: l.text, time: l.time, fresh: !!l.fresh, words: l.words })),
            cursor: doc.cursor, lineCursor: doc.lineCursor, sel: doc.sel
        }));
        if (doc.history.length > 300)
            doc.history.shift();
        doc.dirty = true;
    }

    function undo() {
        const h = doc?.history.pop();
        if (!h)
            return;
        const st = JSON.parse(h);
        doc.lines = st.lines;
        reindex(doc);
        doc.cursor = st.cursor;
        doc.lineCursor = st.lineCursor;
        doc.sel = st.sel;
        rev++;
    }

    function lineTime(l) {
        return l.words.length && l.words[0].time !== null ? l.words[0].time : l.time;
    }

    function playheadAt(pos) {
        if (!doc)
            return -1;
        let p = -1;
        for (let i = 0; i < doc.flat.length; i++) {
            const t = wordAt(i).time;
            if (t === null)
                continue;
            if (t > pos)
                break;
            p = i;
        }
        return p;
    }

    function wordAt(i) {
        const f = doc.flat[i];
        return doc.lines[f.li].words[f.wi];
    }

    // The nearest marked word before (step -1) or after (step 1) word i
    function timedNear(i, step) {
        for (let k = i + step; k >= 0 && k < doc.flat.length; k += step) {
            const t = wordAt(k).time;
            if (t !== null)
                return t;
        }
        return null;
    }

    // Where tapping resumes: the first word (or line) not marked before pos
    function resync(pos) {
        if (!doc)
            return;
        const lines = doc.lines;
        let c = doc.flat.findIndex(f => {
            const t = lines[f.li].words[f.wi].time ?? lines[f.li].time;
            return t === null || t > pos;
        });
        doc.cursor = c < 0 ? doc.flat.length : c;
        c = lines.findIndex(l => lineTime(l) === null || lineTime(l) > pos);
        doc.lineCursor = c < 0 ? lines.length : c;
        rev++;
    }

    function mark() {
        if (!doc || !player)
            return;
        // Taps while paused would all land on the same moment
        if (!player.isPlaying) {
            if (player.canTogglePlaying)
                player.togglePlaying();
            return;
        }
        const t = player.position;
        if (lineMode) {
            const li = doc.lineCursor;
            if (li >= doc.lines.length)
                return;
            remember();
            const l = doc.lines[li];
            l.time = t;
            l.fresh = true;
            l.words.forEach(w => {
                w.time = null;
                w.fresh = false;
            });
            doc.sel = l.base;
            doc.lineCursor = li + 1;
            doc.cursor = doc.lines[li + 1]?.base ?? doc.flat.length;
        } else {
            const c = doc.cursor;
            if (c >= doc.flat.length)
                return;
            remember();
            const w = wordAt(c);
            w.time = t;
            w.fresh = true;
            doc.sel = c;
            doc.cursor = c + 1;
            doc.lineCursor = c + 1 < doc.flat.length ? doc.flat[c + 1].li : doc.lines.length;
        }
        rev++;
        flash.restart();
    }

    function seek(delta) {
        if (!player?.canSeek)
            return;
        const p = Math.max(0, Math.min(player.length - 1, player.position + delta));
        player.position = p;
        now = p;
        resync(p);
    }

    // The selected word is what the fine-tune row acts on; the next tap lands on it too
    function select(i) {
        if (!doc || i < 0 || i >= doc.flat.length)
            return;
        doc.sel = i;
        doc.cursor = i;
        doc.lineCursor = doc.flat[i].li;
        rev++;
    }

    // Up/down through words, or through lines in line mode
    function step(dir) {
        if (!doc?.flat.length)
            return;
        if (doc.sel < 0)
            return select(Math.min(doc.cursor, doc.flat.length - 1));
        if (!lineMode)
            return select(Math.max(0, Math.min(doc.flat.length - 1, doc.sel + dir)));
        const li = Math.max(0, Math.min(doc.lines.length - 1, doc.flat[doc.sel].li + dir));
        select(doc.lines[li].base);
    }

    // Moves the selected word (or the whole line in line mode); a word stays between its neighbours
    function nudge(delta) {
        if (!doc || doc.sel < 0)
            return;
        const f = doc.flat[doc.sel], l = doc.lines[f.li];
        if (lineMode) {
            if (lineTime(l) === null)
                return;
            remember();
            if (l.time !== null)
                l.time = Math.max(0, l.time + delta);
            l.words.forEach(w => {
                if (w.time !== null)
                    w.time = Math.max(0, w.time + delta);
            });
            l.fresh = true;
        } else {
            const w = l.words[f.wi];
            if (w.time === null)
                return;
            const lo = timedNear(doc.sel, -1), hi = timedNear(doc.sel, 1);
            let t = w.time + delta;
            if (lo !== null)
                t = Math.max(t, lo + 0.01);
            if (hi !== null)
                t = Math.min(t, hi - 0.01);
            t = Math.max(0, t);
            if (Math.abs(t - w.time) < 0.001)
                return;
            remember();
            w.time = t;
            w.fresh = true;
        }
        rev++;
    }

    // Drops the selected word's mark (or the line's), so it can be tapped again
    function clearMark() {
        if (!doc || doc.sel < 0)
            return;
        const f = doc.flat[doc.sel], l = doc.lines[f.li];
        remember();
        if (lineMode) {
            l.time = null;
            l.fresh = false;
            l.words.forEach(w => {
                w.time = null;
                w.fresh = false;
            });
            doc.cursor = l.base;
        } else {
            l.words[f.wi].time = null;
            l.words[f.wi].fresh = false;
            doc.cursor = doc.sel;
        }
        doc.lineCursor = f.li;
        rev++;
    }

    function removeLine(li) {
        if (!doc || li < 0 || li >= doc.lines.length)
            return;
        remember();
        doc.lines.splice(li, 1);
        reindex(doc);
        doc.sel = doc.lines.length ? doc.lines[Math.min(li, doc.lines.length - 1)].base : -1;
        resync(now);
    }

    // Plays from just before the selected word. A neighbouring mark caps the start,
    // so a word that was marked far too late can still be heard and tapped again
    function listen() {
        if (!doc || doc.sel < 0 || !player?.canSeek)
            return;
        const f = doc.flat[doc.sel], l = doc.lines[f.li];
        const i = lineMode ? l.base : doc.sel;
        const own = lineMode ? lineTime(l) : (l.words[f.wi].time ?? l.time);
        const before = timedNear(i, -1);
        let from = own;
        if (before !== null && (own === null || (own - before > 0.3 && own - before < 8)))
            from = own === null ? before : Math.min(own, before + 0.3);
        if (from === null)
            return;
        player.position = Math.max(0, from - 1);
        now = player.position;
        if (!player.isPlaying && player.canTogglePlaying)
            player.togglePlaying();
        doc.cursor = i;
        doc.lineCursor = f.li;
        rev++;
    }

    function plainText() {
        return doc ? doc.lines.map(l => l.text).join("\n") : "";
    }

    function setTab(t) {
        if (tab === t)
            return;
        if (tab === "text")
            applyText();
        tab = t;
        if (t === "text")
            edit.text = plainText();
        Qt.callLater(focusIn);
    }

    function norm(w) {
        return w.trim().toLowerCase().replace(/[.,!?…:;"'«»()\[\]—–-]/g, "");
    }

    // Words of an edited line that are still there keep their time (longest common subsequence)
    function merge(oldWords, text) {
        const nw = words({ text: text, words: null });
        const a = oldWords.map(w => norm(w.text)), b = nw.map(w => norm(w.text));
        const n = a.length, m = b.length;
        const dp = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
        for (let i = n - 1; i >= 0; i--)
            for (let k = m - 1; k >= 0; k--)
                dp[i][k] = a[i] === b[k] ? dp[i + 1][k + 1] + 1 : Math.max(dp[i + 1][k], dp[i][k + 1]);
        for (let i = 0, k = 0; i < n && k < m;) {
            if (a[i] === b[k]) {
                nw[k].time = oldWords[i].time;
                i++;
                k++;
            } else if (dp[i + 1][k] >= dp[i][k + 1]) {
                i++;
            } else {
                k++;
            }
        }
        return { words: nw, common: dp[0][0], size: Math.max(n, m) };
    }

    // Untouched lines keep their timing, matched in order a few lines ahead;
    // an edited line keeps the line's time and the words that survived the edit
    function applyText() {
        if (!doc || edit.text === plainText())
            return;
        remember();
        const old = doc.lines;
        let j = 0;
        doc.lines = edit.text.split("\n").map(s => s.trim()).filter(s => s).map(r => {
            for (let s = j; s < Math.min(old.length, j + 8); s++) {
                if (old[s].text.trim() === r) {
                    j = s + 1;
                    return old[s];
                }
            }
            if (j < old.length) {
                const m = merge(old[j].words, r);
                if (m.common * 2 >= m.size) {
                    const time = old[j].time;
                    j++;
                    return { text: r, time: time, words: m.words };
                }
            }
            return { text: r, time: null, words: words({ text: r, words: null }) };
        });
        reindex(doc);
        doc.sel = -1;
        resync(player?.position ?? 0);
    }

    function save() {
        if (!doc || saver.running)
            return;
        if (tab === "text")
            applyText();
        if (!doc.dirty)
            return;
        saver.doc = doc;
        saver.exec(["python3", script, "save", JSON.stringify({
            artist: doc.artist, title: doc.title, duration: doc.duration, source: doc.source, k: doc.k,
            lines: doc.lines.map(l => ({ text: l.text, time: l.time, words: l.words.map(w => ({ text: w.text, time: w.time })) }))
        })]);
    }

    function revert() {
        const d = Object.assign({}, drafts);
        delete d[key];
        drafts = d;
        load();
    }

    function fine(t) {
        if (t === null || t === undefined)
            return "no mark";
        const s = Math.max(0, t);
        return Math.floor(s / 60) + ":" + (s % 60).toFixed(2).padStart(5, "0");
    }

    function stamp(t) {
        if (t === null || t === undefined)
            return "";
        const s = Math.max(0, t);
        return Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0");
    }

    Process {
        id: loader
        property string reqKey
        property var meta
        stdout: StdioCollector {
            onStreamFinished: {
                let data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    data = { lines: [], source: null, k: 1, origin: "none" };
                }
                const d = Object.assign({}, loader.meta, { source: data.source, k: data.k, origin: data.origin, dirty: false, history: [], sel: -1 });
                d.lines = data.lines.map(l => ({ text: l.text, time: l.time, words: root.words(l) }));
                root.reindex(d);
                const all = Object.assign({}, root.drafts);
                all[loader.reqKey] = d;
                root.drafts = all;
                if (loader.reqKey !== root.key)
                    return;
                root.tab = d.lines.length ? "sync" : "text";
                edit.text = root.plainText();
                root.resync(root.player?.position ?? 0);
                Qt.callLater(root.focusIn);
            }
        }
    }

    Process {
        id: saver
        property var doc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (!path)
                    return;
                if (saver.doc.source !== path)
                    saver.doc.k = 1;
                saver.doc.source = path;
                saver.doc.dirty = false;
                root.rev++;
                saved.restart();
                Lyrics.reload();
            }
        }
    }

    Timer {
        id: saved
        interval: 1600
    }

    Timer {
        interval: 100
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            root.now = root.player?.position ?? 0;
            root.playing = root.playheadAt(root.now);
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        // By scancode too, so it works on any layout
        if (ctrl && (event.key === Qt.Key_S || event.nativeScanCode === 39))
            save();
        else if (event.key === Qt.Key_Escape && tab === "sync" && (doc?.sel ?? -1) >= 0) {
            doc.sel = -1;
            rev++;
        } else if (event.key === Qt.Key_Escape)
            root.back();
        else if (tab !== "sync")
            return;
        else if (event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat)
                mark();
        } else if (event.key === Qt.Key_Backspace)
            undo();
        else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier)))
            nudge((event.key === Qt.Key_Left ? -1 : 1) * (event.modifiers & Qt.ShiftModifier ? 0.05 : 0.01));
        else if (event.key === Qt.Key_Left)
            seek(-5);
        else if (event.key === Qt.Key_Right)
            seek(5);
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down)
            step(event.key === Qt.Key_Up ? -1 : 1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            listen();
        else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier))
            removeLine(doc && doc.sel >= 0 ? doc.flat[doc.sel].li : cursorLine);
        else if (event.key === Qt.Key_Delete)
            clearMark();
        else if (event.key === Qt.Key_Tab)
            lineMode = !lineMode;
        else
            return;
        event.accepted = true;
    }

    Column {
        id: column

        width: parent.width
        spacing: 12

        // Header: title, what is playing, save and back
        Item {
            width: parent.width
            height: 28

            Label {
                id: heading
                anchors.verticalCenter: parent.verticalCenter
                text: "Lyrics"
                font.pixelSize: 15
            }

            Label {
                anchors.left: heading.right
                anchors.leftMargin: 10
                anchors.right: actions.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.player?.trackTitle ?? ""
                font.pixelSize: 12
                color: Theme.subtext
                elide: Text.ElideRight
            }

            Row {
                id: actions

                x: parent.width - width + 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (root.rev, root.doc?.dirty ?? false)
                    icon: "history"
                    iconSize: 18
                    diameter: 30
                    onClicked: root.revert()
                }

                // Save: lit while there is something to save, a tick right after
                Rectangle {
                    id: saveBtn

                    readonly property bool dirty: (root.rev, root.doc?.dirty ?? false) || (root.tab === "text" && edit.text !== root.plainText())

                    anchors.verticalCenter: parent.verticalCenter
                    width: saveRow.implicitWidth + 20
                    height: 28
                    radius: 14
                    color: dirty ? Theme.accent : Qt.alpha(Theme.text, saveMouse.containsMouse ? 0.08 : 0)
                    opacity: dirty || saved.running ? 1 : 0.5
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Row {
                        id: saveRow
                        anchors.centerIn: parent
                        spacing: 4

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: saved.running ? "check" : "save"
                            font.pixelSize: 16
                            color: saveBtn.dirty ? Theme.bg : saved.running ? Theme.accent : Theme.subtext
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: saved.running ? "Saved" : "Save"
                            font.pixelSize: 12
                            color: saveBtn.dirty ? Theme.bg : saved.running ? Theme.accent : Theme.subtext
                        }
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.save()
                    }
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "arrow_back"
                    iconSize: 20
                    diameter: 32
                    plain: true
                    onClicked: root.back()
                }
            }
        }

        // Text / Sync, progress, and what one tap marks
        Item {
            width: parent.width
            height: 30
            opacity: root.loading ? 0.4 : 1
            enabled: !root.loading

            Segmented {
                id: tabs
                anchors.verticalCenter: parent.verticalCenter
                options: [["text", "Text", "edit_note"], ["sync", "Sync", "timer"]]
                current: root.tab
                onPicked: v => root.setTab(v)
            }

            Label {
                anchors.left: tabs.right
                anchors.leftMargin: 12
                anchors.right: modes.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: root.tab === "sync" && !!root.doc?.lines.length
                text: root.lineMode ? root.stats.lines + " / " + (root.doc?.lines.length ?? 0) + " lines"
                    : root.stats.words + " / " + (root.doc?.flat.length ?? 0) + " words"
                font.pixelSize: 12
                color: Theme.subtext
                elide: Text.ElideRight
            }

            Segmented {
                id: modes
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.tab === "sync"
                options: [["words", "Words", ""], ["lines", "Lines", ""]]
                current: root.lineMode ? "lines" : "words"
                onPicked: v => {
                    root.lineMode = v === "lines";
                    root.forceActiveFocus();
                }
            }
        }

        Item {
            width: parent.width
            height: 260

            Label {
                anchors.centerIn: parent
                visible: root.loading
                text: "Looking for lyrics…"
                font.pixelSize: 13
                color: Theme.subtext
            }

            // Text: paste or type, one line per row
            Rectangle {
                anchors.fill: parent
                visible: root.tab === "text" && !root.loading
                radius: Theme.radius
                color: Qt.alpha(Theme.surface, 0.75)
                border.width: 1
                border.color: edit.activeFocus ? Qt.alpha(Theme.accent, 0.6) : "transparent"
                Behavior on border.color { ColorAnimation { duration: Theme.anim } }

                Flickable {
                    id: flick

                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: width
                    contentHeight: edit.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    function follow(r) {
                        if (contentY >= r.y)
                            contentY = r.y;
                        else if (contentY + height <= r.y + r.height)
                            contentY = r.y + r.height - height;
                    }

                    TextEdit {
                        id: edit

                        width: flick.width
                        wrapMode: TextEdit.Wrap
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.text
                        selectionColor: Qt.alpha(Theme.accent, 0.4)
                        selectedTextColor: Theme.text
                        selectByMouse: true
                        persistentSelection: true
                        onCursorRectangleChanged: flick.follow(cursorRectangle)

                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                root.setTab("sync");
                                event.accepted = true;
                            }
                        }

                        Label {
                            visible: !edit.text
                            width: parent.width
                            text: "Paste or type the lyrics, one line per row.\nCtrl+Enter to start syncing."
                            font.pixelSize: 13
                            color: Theme.subtext
                            wrapMode: Text.Wrap
                            verticalAlignment: Text.AlignTop
                        }
                    }
                }
            }

            // Sync: the lines around the cursor, word by word
            ListView {
                id: list

                anchors.fill: parent
                visible: root.tab === "sync" && !root.loading
                model: root.doc?.lines.length ?? 0
                currentIndex: root.cursorLine
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                highlight: Item {}
                highlightMoveDuration: 320
                highlightMoveVelocity: -1
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: 70
                preferredHighlightEnd: 120

                delegate: Item {
                    id: row

                    required property int index
                    readonly property var line: (root.rev, root.doc?.lines[index])
                    readonly property bool current: index === root.cursorLine
                    readonly property real start: (root.rev, line ? root.lineTime(line) : null)
                    readonly property bool lineEdited: (root.rev, !!line?.fresh)
                    readonly property bool picked: (root.rev, root.lineMode && (root.doc?.sel ?? -1) >= 0 && root.doc.flat[root.doc.sel].li === index)

                    width: list.width
                    height: flow.implicitHeight + 10
                    opacity: current ? 1 : 0.62
                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                    // The line one tap marks in line mode
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Qt.alpha(Theme.accent, 0.16)
                        border.width: row.picked ? 1.5 : 0
                        border.color: Theme.accent
                        opacity: root.lineMode && (row.picked || row.current && root.doc.lineCursor < root.doc.lines.length) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    }

                    Label {
                        x: 6
                        y: 5
                        width: 34
                        height: 20
                        text: root.stamp(row.start)
                        font.pixelSize: 11
                        color: row.lineEdited || (root.rev, !!row.line?.words[0]?.fresh) ? Theme.accent : Theme.subtext
                    }

                    Flow {
                        id: flow

                        x: 44
                        y: 5
                        width: parent.width - 50
                        spacing: 5

                        Repeater {
                            model: row.line?.words.length ?? 0

                            Item {
                                id: word

                                required property int index
                                readonly property int flat: (root.rev, row.line?.base ?? 0) + index
                                readonly property var w: (root.rev, row.line?.words[index])
                                readonly property bool cursor: !root.lineMode && flat === root.doc?.cursor
                                readonly property bool edited: (root.rev, !!w?.fresh)
                                readonly property bool picked: !root.lineMode && flat === (root.rev, root.doc?.sel)
                                // Redone now: accent. Old timing: plain text with a faint underline. No timing: dim
                                readonly property bool fresh: edited || row.lineEdited
                                readonly property bool timed: (root.rev, w?.time !== null || row.line?.time !== null)

                                width: wordLabel.implicitWidth + 6
                                height: 22

                                Rectangle {
                                    width: parent.width
                                    height: 20
                                    radius: 6
                                    color: Theme.accent
                                    opacity: word.cursor ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                // Selected for fine-tuning
                                Rectangle {
                                    x: -1
                                    y: -1
                                    width: parent.width + 2
                                    height: 22
                                    radius: 7
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: Theme.accent
                                    visible: word.picked
                                }

                                Rectangle {
                                    x: 3
                                    y: 20
                                    width: parent.width - 6
                                    height: 2
                                    radius: 1
                                    visible: word.timed && !word.cursor
                                    color: word.flat === root.playing ? Theme.accent : Qt.alpha(Theme.text, word.fresh ? 0 : 0.28)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Label {
                                    id: wordLabel
                                    x: 3
                                    height: 20
                                    text: word.w?.text.trim() ?? ""
                                    font.pixelSize: 14
                                    font.weight: word.fresh || word.cursor ? Font.DemiBold : Font.Medium
                                    color: word.cursor ? Theme.bg
                                        : word.fresh ? Theme.accent
                                        : word.timed ? Theme.text
                                        : Qt.alpha(Theme.subtext, 0.75)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.select(word.flat);
                                        root.forceActiveFocus();
                                    }
                                    onDoubleClicked: root.listen()
                                }
                            }
                        }
                    }
                }
            }

            // Nothing to sync yet
            Column {
                anchors.centerIn: parent
                visible: list.visible && list.count === 0
                spacing: 10

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No lyrics for this track yet"
                    font.pixelSize: 13
                    color: Theme.subtext
                }

                Pill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: "edit_note"
                    label: "Add text"
                    onClicked: root.setTab("text")
                }
            }
        }

        // Fine-tune the selected word (or line): nudge, listen, drop the mark, delete the line
        Item {
            id: tune

            readonly property int sel: (root.rev, root.doc?.sel ?? -1)
            readonly property var line: sel >= 0 ? (root.rev, root.doc.lines[root.doc.flat[sel].li]) : null
            readonly property var w: sel >= 0 ? (root.rev, line.words[root.doc.flat[sel].wi]) : null
            readonly property var time: !line ? null : root.lineMode ? (root.rev, root.lineTime(line)) : (root.rev, w.time)

            width: parent.width
            height: 30
            visible: root.tab === "sync" && !root.loading && !!root.doc?.lines.length

            Label {
                anchors.centerIn: parent
                visible: tune.sel < 0
                text: "Click a word to fine-tune its timing"
                font.pixelSize: 12
                color: Theme.subtext
            }

            Row {
                anchors.left: parent.left
                anchors.right: tuneButtons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: tune.sel >= 0
                spacing: 8

                Label {
                    id: tuneWord
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - tuneTime.implicitWidth - 8)
                    text: !tune.line ? "" : root.lineMode ? "Line " + (root.doc.flat[tune.sel].li + 1) : tune.w.text.trim()
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.accent
                    elide: Text.ElideRight
                }

                Label {
                    id: tuneTime
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fine(tune.time)
                    font.pixelSize: 12
                    color: Theme.subtext
                }
            }

            Row {
                id: tuneButtons

                anchors.right: parent.right
                anchors.rightMargin: -4
                anchors.verticalCenter: parent.verticalCenter
                visible: tune.sel >= 0
                spacing: 2

                Nudge { label: "−50"; enabled: tune.time !== null; onClicked: root.nudge(-0.05) }
                Nudge { label: "−10"; enabled: tune.time !== null; onClicked: root.nudge(-0.01) }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "hearing"
                    iconSize: 18
                    diameter: 28
                    enabled: root.player?.canSeek ?? false
                    onClicked: {
                        root.listen();
                        root.forceActiveFocus();
                    }
                }

                Nudge { label: "+10"; enabled: tune.time !== null; onClicked: root.nudge(0.01) }
                Nudge { label: "+50"; enabled: tune.time !== null; onClicked: root.nudge(0.05) }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "timer_off"
                    iconSize: 18
                    diameter: 28
                    enabled: tune.time !== null
                    onClicked: {
                        root.clearMark();
                        root.forceActiveFocus();
                    }
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "delete"
                    iconSize: 18
                    diameter: 28
                    onClicked: {
                        root.removeLine(root.doc.flat[tune.sel].li);
                        root.forceActiveFocus();
                    }
                }
            }
        }

        // Transport for tapping: undo, seek, play, tap
        Item {
            width: parent.width
            height: 44
            visible: root.tab === "sync"
            enabled: !root.loading && !!root.doc?.lines.length
            opacity: enabled ? 1 : 0.4

            Label {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.stamp(root.now)
                font.pixelSize: 12
                color: Theme.subtext
            }

            Row {
                anchors.centerIn: parent
                spacing: 8

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "undo"
                    iconSize: 20
                    enabled: (root.rev, (root.doc?.history.length ?? 0) > 0)
                    onClicked: root.undo()
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "replay_5"
                    iconSize: 22
                    plain: true
                    enabled: root.player?.canSeek ?? false
                    onClicked: root.seek(-5)
                }

                // Tap: the big one. Starts playback when paused
                Rectangle {
                    id: tap

                    readonly property bool playing: root.player?.isPlaying ?? false

                    anchors.verticalCenter: parent.verticalCenter
                    width: 112
                    height: 44
                    radius: 22
                    color: Theme.accent
                    scale: tapMouse.pressed || flash.running ? 0.94 : tapMouse.containsMouse ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Timer {
                        id: flash
                        interval: 90
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tap.playing ? "touch_app" : "play_arrow"
                            font.pixelSize: 20
                            color: Theme.bg
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tap.playing ? "Tap" : "Play"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Theme.bg
                        }
                    }

                    MouseArea {
                        id: tapMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.mark();
                            root.forceActiveFocus();
                        }
                    }
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "forward_5"
                    iconSize: 22
                    plain: true
                    enabled: root.player?.canSeek ?? false
                    onClicked: root.seek(5)
                }

                CtrlButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: root.player?.isPlaying ? "pause" : "play_arrow"
                    iconSize: 20
                    enabled: root.player?.canTogglePlaying ?? false
                    onClicked: root.player.togglePlaying()
                }
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.tab === "sync" ? "Space tap · ⌫ undo · ←→ 5 s · Tab words/lines · Ctrl+S save\n"
                    + "↑↓ pick · Shift/Ctrl+←→ ±50/10 ms · Enter listen · Del unmark"
                : "Ctrl+Enter sync · Ctrl+S save · Esc back"
            lineHeight: 1.2
            font.pixelSize: 11
            color: Theme.subtext
            wrapMode: Text.Wrap
        }
    }

    // Small segmented switch: [value, label, icon]
    component Segmented: Rectangle {
        id: seg

        property var options: []
        property string current
        signal picked(string value)

        width: segRow.implicitWidth + 6
        height: 30
        radius: 15
        color: Qt.alpha(Theme.text, 0.06)

        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: seg.options

                Rectangle {
                    id: opt

                    required property var modelData
                    readonly property bool on: seg.current === opt.modelData[0]

                    width: optRow.implicitWidth + 20
                    height: 24
                    radius: 12
                    color: on ? Theme.accent : Qt.alpha(Theme.text, optMouse.containsMouse ? 0.08 : 0)
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Row {
                        id: optRow
                        anchors.centerIn: parent
                        spacing: 4

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!opt.modelData[2]
                            text: opt.modelData[2]
                            font.pixelSize: 15
                            color: opt.on ? Theme.bg : Theme.subtext
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: opt.modelData[1]
                            font.pixelSize: 12
                            color: opt.on ? Theme.bg : Theme.subtext
                        }
                    }

                    MouseArea {
                        id: optMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(opt.modelData[0])
                    }
                }
            }
        }
    }

    component Nudge: Rectangle {
        id: nudge

        property string label
        signal clicked

        anchors.verticalCenter: parent.verticalCenter
        width: 38
        height: 26
        radius: 13
        color: Qt.alpha(Theme.text, nudgeMouse.pressed ? 0.16 : nudgeMouse.containsMouse ? 0.11 : 0.06)
        opacity: enabled ? 1 : 0.35

        Label {
            anchors.centerIn: parent
            text: nudge.label
            font.pixelSize: 11
            color: Theme.text
        }

        MouseArea {
            id: nudgeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                nudge.clicked();
                root.forceActiveFocus();
            }
        }
    }

    component Pill: Rectangle {
        id: pill

        property string icon
        property string label
        signal clicked

        width: pillRow.implicitWidth + 24
        height: 30
        radius: 15
        color: Qt.alpha(Theme.accent, pillMouse.containsMouse ? 0.3 : 0.2)
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                font.pixelSize: 16
                color: Theme.accent
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                font.pixelSize: 13
                color: Theme.accent
            }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
}
