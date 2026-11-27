import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// Clipboard history (cliphist) in the launcher's style
Scope {
    id: root

    onOpenChanged: {
        Sfx.play(open ? "open" : "close");
        Sfx.typingIn("clipboard", open);
    }

    property bool open: false
    property bool mouseActive: false
    property point lastCursor: Qt.point(-1, -1)
    property string query: ""
    property var entries: []

    readonly property int rowHeight: 52
    readonly property int maxRows: 7
    readonly property string thumbDir: Quickshell.env("XDG_CACHE_HOME") ? Quickshell.env("XDG_CACHE_HOME") + "/qs-clipboard" : Quickshell.env("HOME") + "/.cache/qs-clipboard"
    readonly property var imageRe: /^\[\[ binary data .* (png|jpe?g|webp|bmp|gif) /

    readonly property var results: {
        const q = query.trim().toLowerCase();
        return q ? entries.filter(e => !e.image && e.text.toLowerCase().includes(q)) : entries;
    }

    function show() {
        search.clear();
        query = "";
        mouseActive = false;
        lastCursor = Qt.point(-1, -1);
        listProc.running = true;
        resultsView.currentIndex = 0;
        resultsView.positionViewAtBeginning();
        open = true;
        Qt.callLater(() => search.forceActiveFocus());
    }

    function hide() {
        open = false;
    }

    function cursorMoved(item, x, y) {
        const p = item.mapToGlobal(x, y);
        if (p.x === lastCursor.x && p.y === lastCursor.y)
            return false;
        const first = lastCursor.x < 0;
        lastCursor = p;
        if (!first)
            mouseActive = true;
        return mouseActive;
    }

    function copy(entry, paste) {
        if (!entry)
            return;
        const pasteCmd = `win=$(hyprctl activewindow -j)
            sleep 0.2
            case $(echo "$win" | jq -r .class) in
                kitty|foot|Alacritty|com.mitchellh.ghostty|org.wezfurlong.wezterm|org.kde.konsole) mods="CTRL SHIFT" ;;
                *) mods=CTRL ;;
            esac
            addr=$(echo "$win" | jq -r .address)
            hyprctl dispatch 'hl.dsp.send_shortcut({mods="'"$mods"'", key="code:55", window="address:'"$addr"'"})' >/dev/null 2>&1`;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist decode | wl-copy" + (paste ? "\n" + pasteCmd : ""), "sh", entry.id]);
        hide();
    }

    function remove(entry) {
        if (!entry)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t%s\\n' \"$1\" \"$2\" | cliphist delete", "sh", entry.id, entry.raw]);
        const i = resultsView.currentIndex;
        entries = entries.filter(e => e.id !== entry.id);
        resultsView.currentIndex = Math.min(i, resultsView.count - 1);
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down)
            mouseActive = false;

        if (event.key === Qt.Key_Escape)
            hide();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            copy(resultsView.currentItem?.modelData ?? null, !(event.modifiers & Qt.ControlModifier));
        else if (event.key === Qt.Key_Delete)
            remove(resultsView.currentItem?.modelData ?? null);
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
            resultsView.incrementCurrentIndex();
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
            resultsView.decrementCurrentIndex();
        else
            return;
        event.accepted = true;
    }

    // Lists the history and makes thumbnails for new images, dropping stale ones
    Process {
        id: listProc
        command: ["bash", "-c", `
            dir="$1"; mkdir -p "$dir"
            list=$(cliphist list)
            declare -A live
            while IFS=$'\\t' read -r id rest; do
                live[$id]=1
                if [[ $rest =~ ^\\[\\[\\ binary\\ data && ! -f "$dir/$id.png" ]]; then
                    printf '%s\\t\\n' "$id" | cliphist decode \\
                        | magick - -thumbnail 160x90 "$dir/$id.png" 2>/dev/null
                fi
            done <<< "$list"
            for f in "$dir"/*.png; do
                [ -e "$f" ] || continue
                n=\${f##*/}; [ -n "\${live[\${n%.png}]}" ] || rm -f -- "$f"
            done
            printf '%s\\n' "$list"
        `, "bash", root.thumbDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l).map(l => {
                    const tab = l.indexOf("\t");
                    const raw = l.slice(tab + 1);
                    return { id: l.slice(0, tab), raw, text: raw.trim(), image: root.imageRe.test(raw) };
                });
                resultsView.currentIndex = 0;
            }
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }
    }

    PanelWindow {
        visible: root.open || card.opacity > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.namespace: "clipboard"
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

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.open ? 0.3 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        }

        MouseArea {
            onReleased: if (containsMouse) Sfx.tap("click")
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: card

            x: (parent.width - width) / 2
            y: parent.height * 0.2
            width: 560
            height: content.implicitHeight + 24
            radius: Theme.radius + 6
            color: Qt.alpha(Theme.bg, 0.85)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.25)

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: root.open ? Easing.OutBack : Easing.InCubic } }
            Behavior on height {
                enabled: root.open
                NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: content
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.6) : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Theme.anim } }

                    Icon {
                        id: searchIcon
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "content_paste"
                        font.pixelSize: 22
                        color: Theme.accent
                    }

                    TextInput {
                        id: search

                        anchors.left: searchIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font
                        font.pixelSize: 17
                        color: Theme.text
                        selectionColor: Qt.alpha(Theme.accent, 0.4)
                        clip: true
                        focus: true
                        onTextEdited: {
                            root.query = text;
                            resultsView.currentIndex = 0;
                        }
                        Keys.onPressed: event => root.handleKey(event)

                        Label {
                            visible: !search.text
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 17
                            color: Theme.subtext
                            text: root.entries.length ? "Search clipboard" : "Clipboard is empty"
                        }
                    }
                }

                ListView {
                    id: resultsView
                    onCurrentIndexChanged: if (root.open) Sfx.play("hover", 25)

                    width: parent.width
                    height: Math.min(count, root.maxRows) * root.rowHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 160
                    highlightMoveVelocity: -1
                    currentIndex: 0

                    model: ScriptModel {
                        values: root.results
                    }

                    highlight: Rectangle {
                        radius: Theme.radius
                        color: Qt.alpha(Theme.accent, 0.14)
                    }

                    delegate: MouseArea {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool current: ListView.isCurrentItem

                        width: resultsView.width
                        height: root.rowHeight
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onPositionChanged: mouse => {
                            if (root.cursorMoved(row, mouse.x, mouse.y))
                                resultsView.currentIndex = index;
                        }
                        onClicked: event => {
                            if (event.button === Qt.RightButton)
                                root.remove(modelData);
                            else
                                root.copy(modelData, true);
                        }

                        Item {
                            id: lead
                            x: 12
                            width: row.modelData.image ? 64 : 24
                            height: parent.height
                            anchors.verticalCenter: parent.verticalCenter

                            Icon {
                                visible: !row.modelData.image
                                anchors.centerIn: parent
                                text: "notes"
                                font.pixelSize: 20
                                color: row.current ? Theme.accent : Theme.subtext
                            }

                            Image {
                                visible: row.modelData.image
                                anchors.centerIn: parent
                                width: 64
                                height: 40
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                                sourceSize.width: 128
                                source: row.modelData.image ? "file://" + root.thumbDir + "/" + row.modelData.id + ".png" : ""
                            }
                        }

                        Label {
                            anchors.left: lead.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: row.modelData.image ? row.modelData.text.replace(/^\[\[ binary data |\s*\]\]$/g, "") : row.modelData.text
                            color: row.current ? Theme.accent : (row.modelData.image ? Theme.subtext : Theme.text)
                            Behavior on color { ColorAnimation { duration: Theme.anim } }
                        }
                    }
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 12
                    font.weight: Font.Normal
                    color: Theme.subtext
                    text: "Enter paste · Ctrl+Enter copy · Del remove"
                }
            }
        }
    }
}
