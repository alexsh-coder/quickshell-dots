import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    property bool open: false
    property int tagIndex: 0
    // +1 when moving down the tag list, -1 up; picks the strip's slide-in direction
    property int slideDir: 1

    // Accent tuning for the applied wallpaper (A): accent and bar nudges in OKLCH
    property bool tuning: false
    property int tuneRow: 0
    // Which scheme the edits go to; the effective tweak is both + the current scheme's own
    property string tuneScope: "both"
    readonly property var tuneScopes: ["both", "light", "dark"]
    readonly property var tuneRows: [
        { key: "h", group: "Accent", label: "Hue", lim: 60, step: 2, scale: 1, unit: "°" },
        { key: "c", group: "Accent", label: "Chroma", lim: 0.08, step: 0.005, scale: 100, unit: "" },
        { key: "l", group: "Accent", label: "Lightness", lim: 0.3, step: 0.01, scale: 100, unit: "" },
        { key: "bh", group: "Bar", label: "Hue", lim: 60, step: 2, scale: 1, unit: "°" },
        { key: "bc", group: "Bar", label: "Chroma", lim: 0.08, step: 0.005, scale: 100, unit: "" },
        { key: "bl", group: "Bar", label: "Lightness", lim: 0.3, step: 0.01, scale: 100, unit: "" }
    ]

    function tuneSet(row, v) {
        const r = tuneRows[row];
        v = Math.max(-r.lim, Math.min(r.lim, Math.round(v / r.step) * r.step));
        Accent.setTweak(tuneScope, r.key, Math.abs(v) < r.step / 2 ? 0 : +v.toFixed(4));
    }

    function tuneReset() {
        for (let i = 0; i < tuneRows.length; i++)
            tuneSet(i, 0);
    }

    function tuneStep(by) {
        const r = tuneRows[tuneRow];
        tuneSet(tuneRow, (Accent.scopeTweak(tuneScope)[r.key] || 0) + by * r.step);
    }

    readonly property int thumbW: 288
    readonly property int thumbH: 162
    readonly property int gap: 8
    readonly property int tagRow: 36
    readonly property string tagPath: tagIndex < tags.length ? tags[tagIndex].path : ""

    // The strip loops only when there are enough images to fill it; a short tag just sits centered
    readonly property int n: files.count
    readonly property bool loop: n * (thumbW + gap) > stripArea.width + thumbW
    readonly property int laps: loop ? 1000 : 1

    function show() {
        Wallpaper.refresh();
        selectCurrent();
        open = true;
        restore.stop();
        windowsFade("hide");
        Qt.callLater(() => keys.forceActiveFocus());
    }

    function hide() {
        open = false;
        tuning = false;
        windowsFade("show");
    }

    function windowsFade(mode) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/windows-fade.sh", mode]);
    }

    function selectCurrent() {
        const cur = Wallpaper.current;
        for (let i = 0; i < tags.length; i++) {
            if (cur.startsWith(tags[i].path + "/")) {
                tagIndex = i;
                break;
            }
        }
        syncIndex();
    }

    // Lands on the applied wallpaper if it's in this tag, otherwise on the first one
    function syncIndex() {
        let i = 0;
        for (let j = 0; j < n; j++) {
            if (files.get(j, "filePath") === Wallpaper.current) {
                i = j;
                break;
            }
        }
        const target = (loop ? n * Math.floor(laps / 2) : 0) + i;
        strip.currentIndex = target;
        strip.positionViewAtIndex(target, ListView.Center);
    }

    function step(by) {
        if (n === 0)
            return;
        if (loop)
            strip.currentIndex += by;
        else
            strip.currentIndex = Math.max(0, Math.min(n - 1, strip.currentIndex + by));
    }

    function randomOffset() {
        return 1 + Math.floor(Math.random() * (n - 1));
    }

    // Moves to a random other image the short way round, like a normal step
    function pickRandom() {
        if (n < 2)
            return;
        const cur = strip.currentIndex % n;
        const target = (cur + randomOffset()) % n;
        if (!loop) {
            strip.currentIndex = target;
            return;
        }
        let d = target - cur;
        if (d > n / 2)
            d -= n;
        else if (d < -n / 2)
            d += n;
        strip.currentIndex += d;
    }

    function applyRandom() {
        if (n === 0)
            return;
        const cur = files.indexOf("file://" + Wallpaper.current);
        const i = cur < 0 || n < 2 ? Math.floor(Math.random() * n) : (cur + randomOffset()) % n;
        Wallpaper.set(files.get(i, "filePath"));
    }

    function switchTag(by) {
        if (tags.length < 2)
            return;
        slideDir = by;
        tagIndex = (tagIndex + by + tags.length) % tags.length;
    }

    function currentPath() {
        return n > 0 && strip.currentIndex >= 0 ? files.get(strip.currentIndex % n, "filePath") : "";
    }

    function apply(keepOpen) {
        const path = currentPath();
        if (!path)
            return;
        // Leaving a video first freezes it to a still, which pushes the transition back. A new
        // video takes as long as its player needs to start, so that switch reports when it's done
        restore.interval = Wallpaper.isVideo(path) && path !== Wallpaper.current ? 4000 : Wallpaper.video ? 1500 : 900;
        Wallpaper.set(path);
        if (keepOpen)
            return;
        open = false;
        // Windows stay hidden until the wallpaper transition has played out
        restore.restart();
    }

    function prettify(name) {
        return name
            .replace(/[-_.]?\d{3,5}x\d{1,5}([-_.].*)?$/, "")
            .replace(/[-_]+/g, " ")
            .trim() || name;
    }

    Timer {
        id: restore
        interval: 900
        onTriggered: root.windowsFade("show")
    }

    Connections {
        target: Wallpaper
        function onSettled() {
            if (restore.running) {
                restore.stop();
                root.windowsFade("show");
            }
        }
    }

    // Image folders first, then video ones
    readonly property var tags: {
        const out = [];
        for (const [m, dir] of [[imageTags, Wallpaper.dir], [videoTags, Wallpaper.videoDir]])
            for (let i = 0; i < m.count; i++) {
                const path = m.get(i, "filePath");
                if (path.startsWith(dir + "/"))
                    out.push({ name: m.get(i, "fileName"), path: path });
            }
        return out;
    }

    FolderListModel {
        id: imageTags
        folder: "file://" + Wallpaper.dir
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    FolderListModel {
        id: videoTags
        folder: "file://" + Wallpaper.videoDir
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    FolderListModel {
        id: files
        folder: root.tagPath ? "file://" + root.tagPath : ""
        showDirs: false
        caseSensitive: false
        nameFilters: Wallpaper.filters
        sortField: FolderListModel.Name
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                stripIn.restart();
        }
    }

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            if (root.open)
                root.selectCurrent();
        }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }

        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        // Picks from the tag last shown in the picker, so it never wanders into another folder
        function random(): void { root.applyRandom(); }
        function set(path: string): void { Wallpaper.set(path); }
    }

    PanelWindow {
        visible: root.open || panel.opacity > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.namespace: "wallpaper"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                // R on any layout (RU "К" is a different key, same scancode)
                // A toggles accent tuning (RU "Ф", same scancode)
                if (event.key === Qt.Key_A || event.nativeScanCode === 38) {
                    root.tuning = !root.tuning;
                    event.accepted = true;
                    return;
                }
                if (root.tuning) {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.tuning = false;
                        break;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab:
                        root.tuneScope = root.tuneScopes[(root.tuneScopes.indexOf(root.tuneScope) + (event.key === Qt.Key_Backtab ? 2 : 1)) % 3];
                        break;
                    case Qt.Key_Up:
                        root.tuneRow = (root.tuneRow + root.tuneRows.length - 1) % root.tuneRows.length;
                        break;
                    case Qt.Key_Down:
                        root.tuneRow = (root.tuneRow + 1) % root.tuneRows.length;
                        break;
                    case Qt.Key_Left:
                    case Qt.Key_Right:
                        root.tuneStep((event.key === Qt.Key_Left ? -1 : 1) * (event.modifiers & Qt.ShiftModifier ? 5 : 1));
                        break;
                    case Qt.Key_Backspace:
                    case Qt.Key_Delete:
                        if (event.modifiers & Qt.ShiftModifier)
                            root.tuneReset();
                        else
                            root.tuneSet(root.tuneRow, 0);
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_R || event.nativeScanCode === 27) {
                    root.pickRandom();
                    event.accepted = true;
                    return;
                }
                switch (event.key) {
                case Qt.Key_Escape:
                    root.hide();
                    break;
                case Qt.Key_Space:
                    root.apply(true);
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.apply();
                    break;
                case Qt.Key_Left:
                    root.step(-1);
                    break;
                case Qt.Key_Right:
                    root.step(1);
                    break;
                case Qt.Key_Up:
                    root.switchTag(-1);
                    break;
                case Qt.Key_Down:
                    root.switchTag(1);
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }
        }

        Item {
        Rectangle {
            id: tuner

            readonly property bool shown: root.open && root.tuning

            anchors.horizontalCenter: parent.horizontalCenter
            y: panel.y - height - 12 + (shown ? 0 : 12)
            width: 480
            height: tuneCol.implicitHeight + 2 * Theme.pad
            radius: Theme.radius
            color: Theme.bg
            border.width: 1
            border.color: Theme.muted
            visible: opacity > 0
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: tuneCol

                x: Theme.pad
                y: Theme.pad
                width: parent.width - 2 * Theme.pad
                spacing: 6

                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.accent
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.barAccent
                    }

                    Label {
                        font.pixelSize: 13
                        color: Theme.subtext
                        text: "Accent for " + root.prettify(Wallpaper.current.split("/").pop().replace(/\.[^.]*$/, ""))
                        width: parent.width - 48
                        elide: Text.ElideRight
                    }
                }

                Item {
                    width: parent.width
                    height: 24 + 8

                    Row {
                        spacing: 6

                        Repeater {
                            model: root.tuneScopes

                            Rectangle {
                                id: chip

                                required property string modelData
                                readonly property bool on: root.tuneScope === modelData

                                width: chipText.implicitWidth + 20
                                height: 24
                                radius: 12
                                color: on ? Theme.accent : "transparent"
                                border.width: 1
                                border.color: on ? Theme.accent : Theme.muted

                                Label {
                                    id: chipText
                                    anchors.centerIn: parent
                                    font.pixelSize: 12
                                    color: chip.on ? Theme.bg : Theme.subtext
                                    text: chip.modelData === "both" ? "Both themes" : chip.modelData === "light" ? "Light" : "Dark"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.tuneScope = chip.modelData
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        width: resetText.implicitWidth + 20
                        height: 24
                        radius: 12
                        color: resetArea.containsMouse ? Theme.muted : "transparent"
                        border.width: 1
                        border.color: Theme.muted

                        Label {
                            id: resetText
                            anchors.centerIn: parent
                            font.pixelSize: 12
                            color: Theme.subtext
                            text: "Reset"
                        }

                        MouseArea {
                            id: resetArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.tuneReset()
                        }
                    }
                }

                Repeater {
                    model: root.tuneRows

                    Row {
                        id: tuneLine

                        required property int index
                        required property var modelData
                        readonly property real value: Accent.scopeTweak(root.tuneScope)[modelData.key] || 0

                        spacing: 10
                        height: 26

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 150
                            font.pixelSize: 13
                            color: tuneLine.index === root.tuneRow ? Theme.accent : Theme.subtext
                            text: tuneLine.modelData.group + " · " + tuneLine.modelData.label
                        }

                        Slider {
                            anchors.verticalCenter: parent.verticalCenter
                            width: tuneCol.width - 226
                            dim: tuneLine.index !== root.tuneRow
                            value: (tuneLine.value / tuneLine.modelData.lim + 1) / 2
                            onMoved: v => {
                                root.tuneRow = tuneLine.index;
                                root.tuneSet(tuneLine.index, (v * 2 - 1) * tuneLine.modelData.lim);
                            }
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 46
                            horizontalAlignment: Text.AlignRight
                            font.pixelSize: 13
                            text: (tuneLine.value > 0 ? "+" : "") + +(tuneLine.value * tuneLine.modelData.scale).toFixed(1) + tuneLine.modelData.unit
                        }
                    }
                }

                Label {
                    font.pixelSize: 12
                    color: Theme.subtext
                    text: "↑↓ row  ←→ adjust  Tab theme  ⌫ reset (Shift: all)  A close"
                }
            }
        }

            id: panel

            readonly property int margin: 28

            width: parent.width
            height: root.thumbH + 56
            y: root.open ? parent.height - height - margin : parent.height - height * 0.5

            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            Behavior on y {
                NumberAnimation {
                    duration: Theme.anim + 80
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emphasizedDecel
                }
            }

            // No backdrop, so a soft shadow keeps thumbnails and text readable on any wallpaper
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "black"
                shadowOpacity: 0.7
                shadowBlur: 0.8
                shadowVerticalOffset: 2
            }

            MouseArea {
                anchors.fill: parent
                onWheel: wheel => root.step((wheel.angleDelta.y || wheel.angleDelta.x) < 0 ? 1 : -1)
            }

            ListView {
                id: tagList

                z: 1

                x: panel.margin
                y: (root.thumbH - height) / 2
                width: 132
                height: Math.min(root.thumbH, count * root.tagRow)
                clip: true
                interactive: false
                model: root.tags
                currentIndex: root.tagIndex
                highlightMoveDuration: Theme.anim
                highlightMoveVelocity: -1

                highlight: Item {
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height * 0.5
                        radius: 2
                        color: Theme.accent
                    }
                }

                delegate: Item {
                    id: tagItem

                    required property int index
                    required property var modelData
                    readonly property bool current: index === root.tagIndex

                    width: tagList.width
                    height: root.tagRow

                    FolderListModel {
                        id: tagFiles
                        folder: "file://" + tagItem.modelData.path
                        showDirs: false
                        caseSensitive: false
                        nameFilters: files.nameFilters
                    }

                    Label {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 50
                        elide: Text.ElideRight
                        text: tagItem.modelData.name
                        color: tagItem.current ? Theme.text : Theme.subtext
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }

                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: tagFiles.count
                        font.pixelSize: 13
                        color: tagItem.current ? Theme.accent : Theme.subtext
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.slideDir = tagItem.index > root.tagIndex ? 1 : -1;
                            root.tagIndex = tagItem.index;
                        }
                    }
                }
            }

            Item {
                id: stripArea

                width: parent.width
                height: parent.height
                transform: Translate { id: stripShift }

                ParallelAnimation {
                    id: stripIn
                    NumberAnimation { target: stripArea; property: "opacity"; from: 0; to: 1; duration: Theme.anim }
                    NumberAnimation {
                        target: stripShift
                        property: "y"
                        from: root.slideDir * 24
                        to: 0
                        duration: Theme.anim + 80
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.emphasizedDecel
                    }
                }

                // Children render into a layer the size of this item, so tiles get cut here and faded by the mask
                Item {
                    id: stripClip

                    width: parent.width
                    height: root.thumbH
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: fadeMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    ListView {
                        id: strip

                        x: root.loop ? 0 : (parent.width - width) / 2
                        width: root.loop ? parent.width : Math.min(parent.width, root.n * (root.thumbW + root.gap) - root.gap)
                        height: root.thumbH
                        interactive: false
                        orientation: ListView.Horizontal
                        spacing: root.gap
                        model: root.n * root.laps
                        highlightRangeMode: root.loop ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                        preferredHighlightBegin: (width - root.thumbW) / 2
                        preferredHighlightEnd: (width + root.thumbW) / 2
                        highlightMoveDuration: 260
                        onCountChanged: root.syncIndex()

                        delegate: Item {
                            id: tile

                            required property int index
                            readonly property int real: index % root.n
                            readonly property string filePath: files.get(real, "filePath")
                            readonly property bool selected: ListView.isCurrentItem
                            readonly property bool applied: filePath === Wallpaper.current
                            // 0 at the center of the screen, 1 at the strip's edges
                            readonly property real dist: {
                                const c = x - strip.contentX + strip.x + width / 2;
                                const half = stripArea.width / 2;
                                return Math.min(1, Math.abs(c - half) / half);
                            }

                            width: root.thumbW
                            height: root.thumbH
                            scale: selected ? 1 : 0.82
                            opacity: 1 - dist * 0.5
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: Theme.radius
                                color: Qt.alpha(Theme.bg, 0.6)

                                Image {
                                    id: thumb

                                    readonly property string url: "file://" + Wallpaper.thumb(tile.filePath)

                                    anchors.fill: parent
                                    source: url
                                    sourceSize.width: root.thumbW * 2
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                                    // A video's poster may still be on its way when the tile shows up
                                    Connections {
                                        target: Wallpaper
                                        function onPostersChanged() {
                                            if (thumb.status !== Image.Error)
                                                return;
                                            thumb.source = "";
                                            thumb.source = Qt.binding(() => thumb.url);
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radius
                                color: "transparent"
                                border.width: 2
                                border.color: tile.selected ? Theme.accent : "transparent"
                                Behavior on border.color { ColorAnimation { duration: Theme.anim } }
                            }

                            Rectangle {
                                visible: tile.applied
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                width: 24
                                height: 24
                                radius: 12
                                color: Theme.accent

                                Icon {
                                    anchors.centerIn: parent
                                    text: "check"
                                    font.pixelSize: 18
                                    color: Theme.bg
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (tile.selected)
                                        root.apply();
                                    else
                                        strip.currentIndex = tile.index;
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: fadeMask

                    // Fully hidden over the tags (mirrored on the right to stay centered), then a soft ramp
                    readonly property real hidden: (tagList.x + tagList.width + 16) / width
                    readonly property real edge: hidden + root.thumbW * 0.7 / width

                    width: stripClip.width
                    height: stripClip.height
                    visible: false
                    layer.enabled: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: fadeMask.hidden; color: "transparent" }
                        GradientStop { position: fadeMask.edge; color: "white" }
                        GradientStop { position: 1 - fadeMask.edge; color: "white" }
                        GradientStop { position: 1 - fadeMask.hidden; color: "transparent" }
                    }
                }

                Label {
                    x: (parent.width - width) / 2
                    y: strip.height + 14
                    width: Math.min(implicitWidth, root.thumbW * 2)
                    elide: Text.ElideRight
                    font.pixelSize: 14
                    text: root.n === 0
                          ? (root.tags.length === 0 ? "No folders in " + Wallpaper.dir + " or " + Wallpaper.videoDir : "Nothing here")
                          : root.prettify(files.get(strip.currentIndex % root.n, "fileBaseName") ?? "")
                }

                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: panel.margin
                    y: strip.height + 14
                    visible: root.n > 0
                    font.pixelSize: 13
                    color: Theme.subtext
                    text: (strip.currentIndex % root.n + 1) + " / " + root.n
                }
            }
        }
    }
}
