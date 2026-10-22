import QtQuick
import qs.config
import qs.components
import qs.services

// The desktop editor's side panel: which preset this wallpaper shows, its widgets and effects,
// and the wallpaper's accent
Rectangle {
    id: root

    property string tab: "widgets"
    property bool menu: false
    // The preset being renamed in the menu
    property string renameId: ""
    // Preset being dragged in the menu: where it came from and where its row's top is, in rows
    property int dragFrom: -1
    property real dragPos: 0
    readonly property int dragSlot: Math.round(dragPos)
    // The dropped row's leftover offset, picked up by its new delegate to settle into place
    property string dropId: ""
    property real dropRest: 0
    // Effect groups expanded in the Effects tab; all start folded
    property var openFx: []
    readonly property var sel: Desk.widget(Desk.selected)
    readonly property string wallName: Wallpaper.current.split("/").pop().replace(/\.[^.]*$/, "").replace(/[-_]+/g, " ")
    // Assigned explicitly, or showing the fallback
    readonly property bool own: Wallpaper.current in Desk.walls

    // Accent nudges in OKLCH, for both themes or one (see Accent.setTweak)
    property string tuneScope: "both"
    readonly property var tuneRows: [
        { key: "h", group: "Accent", label: "Hue", lim: 60, step: 2, unit: "°" },
        { key: "c", group: "Accent", label: "Chroma", lim: 0.08, step: 0.005 },
        { key: "l", group: "Accent", label: "Lightness", lim: 0.3, step: 0.01 },
        { key: "bh", group: "Bar", label: "Hue", lim: 60, step: 2, unit: "°" },
        { key: "bc", group: "Bar", label: "Chroma", lim: 0.08, step: 0.005 },
        { key: "bl", group: "Bar", label: "Lightness", lim: 0.3, step: 0.01 }
    ]

    function presetLabel(id) {
        if (id === "")
            return "Empty";
        return Desk.presets[id]?.name ?? "";
    }

    function rows(w) {
        return (Desk.kinds[w.type]?.schema ?? []).filter(r => !r.only || r.only.includes(w.style ?? w.layout ?? "lines"));
    }

    color: Qt.alpha(Theme.bg, 0.94)
    radius: Theme.radius + 6
    border.width: 1
    border.color: Theme.muted

    // Clicks stay in the panel
    MouseArea {
        anchors.fill: parent
        onWheel: wheel => {}
    }

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.margins: Theme.pad
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col

            width: flick.width
            spacing: 14

            // Header
            Item {
                width: parent.width
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40

                    Label {
                        text: "Desktop"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Label {
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: root.wallName
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.muted : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        text: "close"
                        font.pixelSize: 20
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Desk.editing = false
                    }
                }
            }

            // Preset of this wallpaper
            Rectangle {
                width: parent.width
                height: presetCol.implicitHeight + 24
                radius: Theme.radius
                color: Theme.surface

                Column {
                    id: presetCol

                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 30

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 40
                            elide: Text.ElideRight
                            text: root.presetLabel(Desk.currentId) + (root.own ? "" : "  ·  fallback")
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 15
                            color: menuArea.containsMouse || root.menu ? Theme.muted : "transparent"

                            Icon {
                                anchors.centerIn: parent
                                text: root.menu ? "expand_less" : "expand_more"
                                font.pixelSize: 22
                            }

                            MouseArea {
                                id: menuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.menu = !root.menu
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: Theme.subtext
                        text: {
                            const id = Desk.currentId;
                            if (id === "")
                                return "Nothing on the desktop for this wallpaper.";
                            const n = Desk.usage(id);
                            if (id === Desk.fallback)
                                return "The fallback: every wallpaper without its own preset shows it" + (n ? `, and ${n} more chose it.` : ".");
                            return n > 1 ? `Shared by ${n} wallpapers: edits show on all of them.` : "Only this wallpaper uses it.";
                        }
                    }

                    // Every preset, the fallback and nothing at all
                    Column {
                        visible: root.menu
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: [null].concat(Desk.presetIds).concat([""])

                            Rectangle {
                                id: option

                                required property var modelData
                                required property int index
                                // Index among the presets, which are the only rows that move
                                readonly property int slot: index - 1
                                readonly property real step: height + 2
                                readonly property bool held: root.dragFrom >= 0 && root.dragFrom === slot && real
                                property real grabY: 0
                                property real offset: 0
                                property real shift: real && root.dragFrom >= 0 && !held ? (root.dragFrom < slot && slot <= root.dragSlot ? -step : root.dragSlot <= slot && slot < root.dragFrom ? step : 0) : 0

                                Behavior on shift { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                                NumberAnimation on offset { id: settle; running: false; to: 0; duration: Theme.anim; easing.type: Easing.OutCubic }

                                Component.onCompleted: {
                                    if (modelData === root.dropId && root.dropId) {
                                        offset = root.dropRest;
                                        root.dropId = "";
                                        settle.start();
                                    }
                                }

                                transform: Translate { y: option.held ? (root.dragPos - option.slot) * option.step : option.offset + option.shift }
                                z: held ? 10 : 0
                                border.width: held ? 1 : 0
                                border.color: Qt.alpha(Theme.accent, 0.4)
                                // null: follow the fallback
                                readonly property bool picked: modelData === null ? !root.own : root.own && Desk.walls[Wallpaper.current] === modelData

                                width: parent.width
                                height: 32
                                radius: 8
                                color: optionHover.hovered && !renaming ? Theme.muted : picked ? Qt.alpha(Theme.accent, 0.14) : "transparent"

                                // A real preset, which can be renamed, made the fallback or deleted
                                readonly property bool real: typeof modelData === "string" && modelData !== ""
                                readonly property bool renaming: real && root.renameId === modelData
                                property string tip: ""

                                HoverHandler {
                                    id: optionHover
                                }

                                MouseArea {
                                    id: optionArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: option.held ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    preventStealing: option.held
                                    property bool dragged: false
                                    onPressed: mouse => {
                                        dragged = false;
                                        option.grabY = mapToItem(option.parent, mouse.x, mouse.y).y;
                                    }
                                    onPositionChanged: mouse => {
                                        // In the column's coordinates: the row itself moves under the cursor
                                        const y = mapToItem(option.parent, mouse.x, mouse.y).y;
                                        if (!option.real || option.renaming || !(pressedButtons & Qt.LeftButton))
                                            return;
                                        if (!dragged && Math.abs(y - option.grabY) > Application.styleHints.startDragDistance) {
                                            dragged = true;
                                            root.dragFrom = option.slot;
                                        }
                                        if (dragged)
                                            root.dragPos = Math.max(0, Math.min(Desk.presetIds.length - 1, option.slot + (y - option.grabY) / option.step));
                                    }
                                    function drop() {
                                        if (root.dragFrom < 0)
                                            return;
                                        const ids = Desk.presetIds.slice();
                                        ids.splice(root.dragSlot, 0, ids.splice(root.dragFrom, 1)[0]);
                                        root.dropId = option.modelData;
                                        root.dropRest = (root.dragPos - root.dragSlot) * option.step;
                                        root.dragFrom = -1;
                                        Desk.reorder(ids);
                                    }
                                    onReleased: drop()
                                    onCanceled: drop()
                                    onClicked: {
                                        if (dragged)
                                            return;
                                        Desk.assign(Wallpaper.current, option.modelData);
                                        root.menu = false;
                                    }
                                }

                                Label {
                                    visible: !option.renaming
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: actions.x - 16
                                    elide: Text.ElideRight
                                    font.pixelSize: 14
                                    color: option.picked ? Theme.accent : Theme.text
                                    text: option.modelData === null ? "Fallback (" + root.presetLabel(Desk.fallback) + ")" : root.presetLabel(option.modelData)
                                }

                                TextInput {
                                    id: nameInput

                                    visible: option.renaming
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: actions.x - 16
                                    clip: true
                                    color: Theme.text
                                    selectionColor: Theme.accent
                                    selectedTextColor: Theme.bg
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    onVisibleChanged: {
                                        if (!visible)
                                            return;
                                        text = Desk.presets[option.modelData]?.name ?? "";
                                        selectAll();
                                        forceActiveFocus();
                                    }
                                    function finish(save) {
                                        if (save)
                                            Desk.rename(option.modelData, text);
                                        root.renameId = "";
                                    }
                                    Keys.onReturnPressed: finish(true)
                                    Keys.onEnterPressed: finish(true)
                                    Keys.onEscapePressed: finish(false)
                                    onActiveFocusChanged: {
                                        if (!activeFocus && option.renaming)
                                            finish(true);
                                    }
                                }

                                // Usage count, or what the hovered action does
                                Label {
                                    anchors.right: actions.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: option.real && !option.renaming
                                    font.pixelSize: 12
                                    color: option.tip ? Theme.text : Theme.subtext
                                    text: option.tip || (visible ? Desk.usage(option.modelData) || "" : "")
                                }

                                Row {
                                    id: actions

                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: (option.real || option.modelData === "") && optionHover.hovered && !option.renaming
                                    spacing: 2

                                    Repeater {
                                        model: option.real ? [
                                            { icon: "edit", tip: "Rename", run: () => root.renameId = option.modelData },
                                            { icon: "star", tip: "Make fallback", hide: option.modelData === Desk.fallback, run: () => Desk.setFallback(option.modelData) },
                                            { icon: "delete", tip: "Delete", hide: option.modelData === Desk.fallback, run: () => Desk.remove(option.modelData) }
                                        ].filter(a => !a.hide) : option.modelData === "" && Desk.fallback !== "" ? [
                                            { icon: "star", tip: "Make fallback", run: () => Desk.setFallback("") }
                                        ] : []

                                        Rectangle {
                                            required property var modelData
                                            width: 26
                                            height: 26
                                            radius: 13
                                            color: actArea.containsMouse ? Qt.alpha(Theme.text, 0.12) : "transparent"

                                            Icon {
                                                anchors.centerIn: parent
                                                text: parent.modelData.icon
                                                font.pixelSize: 16
                                                color: actArea.containsMouse ? Theme.text : Theme.subtext
                                            }

                                            MouseArea {
                                                id: actArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onContainsMouseChanged: option.tip = containsMouse ? parent.modelData.tip : ""
                                                onClicked: {
                                                    option.tip = "";
                                                    parent.modelData.run();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        Chip {
                            icon: "content_copy"
                            text: "Own copy"
                            visible: Desk.currentId === "" || Desk.currentId === Desk.fallback || Desk.usage(Desk.currentId) > 1
                            onClicked: Desk.own(Wallpaper.current)
                        }
                        Chip {
                            icon: "add"
                            text: "New"
                            onClicked: Desk.assign(Wallpaper.current, Desk.create("New preset"))
                        }
                    }
                }
            }

            // Tabs
            Row {
                spacing: 6

                Repeater {
                    model: [["widgets", "Widgets", "widgets"], ["effects", "Effects", "auto_awesome"], ["accent", "Accent", "palette"]]

                    Chip {
                        required property var modelData
                        icon: modelData[2]
                        text: modelData[1]
                        on: root.tab === modelData[0]
                        onClicked: root.tab = modelData[0]
                    }
                }
            }

            // Widgets: the list, adding, and the selected one's settings
            Column {
                visible: root.tab === "widgets"
                width: parent.width
                spacing: 12

                // Master switch for every preset
                Item {
                    width: parent.width
                    height: 32

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Show widgets"
                        font.pixelSize: 14
                    }

                    Label {
                        anchors.right: masterSwitch.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "all presets"
                        font.pixelSize: 12
                        color: Theme.subtext
                    }

                    Toggle {
                        id: masterSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Desk.widgetsOn
                        onToggled: Desk.setWidgetsOn(!Desk.widgetsOn)
                    }
                }

                Column {
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: Desk.widgets.slice().reverse()

                        Rectangle {
                            id: item

                            required property var modelData
                            readonly property bool picked: Desk.selection.includes(modelData.id)

                            width: parent.width
                            height: 36
                            radius: 8
                            color: picked ? Qt.alpha(Theme.accent, 0.16) : itemArea.containsMouse ? Theme.surface : "transparent"

                            Row {
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Desk.kinds[item.modelData.type]?.icon ?? "widgets"
                                    font.pixelSize: 20
                                    fill: item.picked ? 1 : 0
                                    color: item.picked ? Theme.accent : Theme.text
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 14
                                    color: item.picked ? Theme.accent : item.modelData.hidden ? Theme.subtext : Theme.text
                                    text: (Desk.kinds[item.modelData.type]?.name ?? item.modelData.type) + (item.modelData.style ? "  ·  " + item.modelData.style : "")
                                }
                            }

                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => Desk.select(item.picked && !(mouse.modifiers & Qt.ControlModifier) ? "" : item.modelData.id, mouse.modifiers & Qt.ControlModifier)
                            }

                            // Hide without deleting
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 14
                                color: eyeArea.containsMouse ? Theme.muted : "transparent"

                                Icon {
                                    anchors.centerIn: parent
                                    text: item.modelData.hidden ? "visibility_off" : "visibility"
                                    font.pixelSize: 18
                                    color: item.modelData.hidden ? Theme.subtext : Theme.text
                                }

                                MouseArea {
                                    id: eyeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Desk.setWidget(item.modelData.id, "hidden", !item.modelData.hidden)
                                }
                            }
                        }
                    }

                    Label {
                        visible: Desk.widgets.length === 0
                        font.pixelSize: 13
                        color: Theme.subtext
                        text: "No widgets yet. Add one:"
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Object.keys(Desk.kinds)

                        Chip {
                            required property string modelData
                            icon: "add"
                            text: Desk.kinds[modelData].name
                            onClicked: Desk.addWidget(modelData)
                        }
                    }
                }

                Rectangle {
                    visible: !!root.sel
                    width: parent.width
                    height: 1
                    color: Theme.muted
                }

                Column {
                    visible: !!root.sel
                    width: parent.width
                    spacing: 12

                    Item {
                        width: parent.width
                        height: 28

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sel ? Desk.kinds[root.sel.type]?.name ?? "" : ""
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            spacing: 4

                            Chip { icon: "arrow_upward"; onClicked: Desk.restack(Desk.selected, 1) }
                            Chip { icon: "arrow_downward"; onClicked: Desk.restack(Desk.selected, -1) }
                            Chip { icon: "content_copy"; onClicked: Desk.duplicateWidget(Desk.selected) }
                            Chip { icon: "restart_alt"; onClicked: Desk.resetWidget(Desk.selected) }
                            Chip { icon: "delete"; onClicked: Desk.removeWidget(Desk.selected) }
                        }
                    }

                    Repeater {
                        model: root.sel ? root.rows(root.sel) : []

                        PropRow {
                            required property var modelData
                            width: parent.width
                            row: modelData
                            value: root.sel ? root.sel[modelData.key] ?? Desk.kinds[root.sel.type].props[modelData.key] : undefined
                            initial: root.sel ? Desk.kinds[root.sel.type].props[modelData.key] : undefined
                            onEdited: v => Desk.setWidget(Desk.selected, modelData.key, v)
                            onReset: Desk.resetWidget(Desk.selected, modelData.key)
                        }
                    }
                }
            }

            // Effects over the wallpaper, from the preset
            Column {
                visible: root.tab === "effects"
                width: parent.width
                spacing: 6

                // Master switch for every preset
                Item {
                    width: parent.width
                    height: 32

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wallpaper effects"
                        font.pixelSize: 14
                    }

                    Label {
                        anchors.right: fxSwitch.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "all presets"
                        font.pixelSize: 12
                        color: Theme.subtext
                    }

                    Toggle {
                        id: fxSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Desk.fxOn
                        onToggled: Desk.setFxOn(!Desk.fxOn)
                    }
                }

                Label {
                    visible: Desk.currentId === ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    color: Theme.subtext
                    text: "Effects come with a preset; this wallpaper has none."
                }

                Repeater {
                    model: Desk.currentId === "" ? [] : Desk.fxSchema

                    Column {
                        id: fxRow

                        required property int index
                        required property var modelData

                        width: parent.width
                        spacing: 8

                        readonly property bool open: root.openFx.includes(modelData.group)
                        readonly property bool first: index === 0 || Desk.fxSchema[index - 1].group !== modelData.group

                        visible: first || open

                        Item {
                            visible: fxRow.index === 0 || Desk.fxSchema[fxRow.index - 1].group !== fxRow.modelData.group
                            width: parent.width
                            height: 32

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: fxRow.modelData.group
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Icon {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "expand_more"
                                font.pixelSize: 20
                                color: Theme.subtext
                                rotation: fxRow.open ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const g = fxRow.modelData.group;
                                    root.openFx = fxRow.open ? root.openFx.filter(x => x !== g) : root.openFx.concat([g]);
                                }
                            }
                        }

                        PropRow {
                            visible: fxRow.open
                            width: parent.width
                            row: fxRow.modelData
                            value: Object.assign({}, Desk.fxDefaults, Desk.current?.fx ?? {})[fxRow.modelData.key]
                            initial: Desk.fxDefaults[fxRow.modelData.key]
                            onEdited: v => Desk.setFx(fxRow.modelData.key, v)
                            onReset: Desk.setFx(fxRow.modelData.key, Desk.fxDefaults[fxRow.modelData.key])
                        }
                    }
                }
            }

            // This wallpaper's accent
            Column {
                visible: root.tab === "accent"
                width: parent.width
                spacing: 12

                Row {
                    spacing: 10

                    Rectangle { width: 28; height: 28; radius: 14; color: Theme.accent }
                    Rectangle { width: 28; height: 28; radius: 14; color: Theme.barAccent }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 13
                        color: Theme.subtext
                        text: "Accent and bar"
                    }
                }

                Row {
                    spacing: 6

                    Repeater {
                        model: [["both", "Both themes"], ["light", "Light"], ["dark", "Dark"]]

                        Chip {
                            required property var modelData
                            text: modelData[1]
                            on: root.tuneScope === modelData[0]
                            onClicked: root.tuneScope = modelData[0]
                        }
                    }
                }

                Repeater {
                    model: root.tuneRows

                    PropRow {
                        required property var modelData
                        width: parent.width
                        row: ({ label: modelData.group + " · " + modelData.label, min: -modelData.lim, max: modelData.lim, step: modelData.step, unit: modelData.unit })
                        value: Accent.scopeTweak(root.tuneScope)[modelData.key] || 0
                        onEdited: v => Accent.setTweak(root.tuneScope, modelData.key, Math.abs(v) < modelData.step / 2 ? 0 : v)
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Chip {
                        icon: "restart_alt"
                        text: "Reset"
                        onClicked: root.tuneRows.forEach(r => Accent.setTweak(root.tuneScope, r.key, 0))
                    }
                    Chip {
                        icon: "invert_colors"
                        text: "Invert wallpaper"
                        visible: Wallpaper.isMono(Wallpaper.current)
                        on: !!Wallpaper.inverted[Wallpaper.current]
                        onClicked: Wallpaper.invert(Wallpaper.current)
                    }
                    Chip {
                        icon: Theme.light ? "dark_mode" : "light_mode"
                        text: Theme.light ? "Dark theme" : "Light theme"
                        onClicked: Scheme.toggle()
                    }
                }
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                topPadding: 6
                font.pixelSize: 11
                color: Theme.subtext
                text: "Drag to move, corners resize (Shift: keep shape, Alt: no snapping). Arrows nudge, Del removes, Ctrl+D duplicates, Ctrl+Z undoes. H hides the panel, Esc closes."
            }
        }
    }
}
