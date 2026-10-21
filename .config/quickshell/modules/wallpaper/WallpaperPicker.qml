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
        // Leaving a video first freezes it to a still, which pushes the transition back
        restore.interval = Wallpaper.video ? 1500 : 900;
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

    // Image folders first, then video ones
    readonly property var tags: {
        const out = [];
        for (const m of [imageTags, videoTags])
            for (let i = 0; i < m.count; i++)
                out.push({ name: m.get(i, "fileName"), path: m.get(i, "filePath") });
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
