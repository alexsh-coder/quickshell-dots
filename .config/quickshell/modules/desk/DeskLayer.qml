import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The desktop widgets of the shown preset, on the desktop layer: under windows, click-through.
// Widgets are matched by id across presets, so the same widget glides from one layout to the next
PanelWindow {
    id: root

    // Rows: wid, type, json (the widget's settings), gone (fading out), order (stacking).
    // A widget takes over a shown one with the same id, else one of its type (same style first),
    // so a clock in one preset glides to where the next preset has its clock
    function sync() {
        const list = Desk.widgets;
        const rows = [];
        for (let j = 0; j < live.count; j++)
            if (!live.get(j).gone)
                rows.push(j);
        const taken = new Set(), match = {};
        const claim = test => list.forEach((w, i) => {
            if (i in match)
                return;
            const j = rows.find(r => !taken.has(r) && live.get(r).type === w.type && test(live.get(r), w));
            if (j !== undefined) {
                taken.add(j);
                match[i] = j;
            }
        });
        claim((r, w) => r.wid === w.id);
        claim((r, w) => JSON.parse(r.json).style === w.style);
        claim(() => true);
        for (const j of rows)
            if (!taken.has(j))
                live.setProperty(j, "gone", true);
        list.forEach((w, i) => {
            const json = JSON.stringify(w);
            if (i in match) {
                const j = match[i];
                live.setProperty(j, "wid", w.id);
                if (live.get(j).json !== json)
                    live.setProperty(j, "json", json);
                live.setProperty(j, "order", i);
            } else {
                live.append({ wid: w.id, type: w.type, json: json, gone: false, order: i });
            }
        });
        reap.restart();
    }

    // Only mapped while something shows: visualizers alone stay unmapped without music
    readonly property bool needed: (Desk.widgetsOn || Desk.editing) && Desk.widgets.some(w => w.type !== "visualizer") || Desk.widgets.length > 0 && (Desk.editing || MusicFx.desktop && Cava.active)

    visible: needed || hold.running
    onNeededChanged: {
        if (!needed)
            hold.restart();
    }

    // Lets the widgets fade out before the layer goes
    Timer {
        id: hold
        interval: Desk.morphTime
    }

    WlrLayershell.namespace: "desk"
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

    ListModel {
        id: live
    }

    // After a wallpaper switch the morph flag is up by the time this runs
    Connections {
        target: Desk
        function onWidgetsChanged() {
            Qt.callLater(root.sync);
        }
    }

    Component.onCompleted: sync()

    // Widgets that faded out
    Timer {
        id: reap
        interval: Desk.morphTime
        onTriggered: {
            for (let i = live.count - 1; i >= 0; i--)
                if (live.get(i).gone)
                    live.remove(i);
        }
    }

    Repeater {
        model: live

        DeskWidget {
            required property int order

            z: order
            sw: root.width
            sh: root.height
        }
    }
}
