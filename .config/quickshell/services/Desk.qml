pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Desktop widgets, grouped into presets. Every wallpaper shows the fallback preset unless it has
// one assigned in `walls` ("" there means nothing at all). A widget's rect is its centre and size
// as fractions of the screen, so a layout fits any monitor; its content keeps its own proportions
// inside. Each preset also carries the music effects drawn over the wallpaper (see MusicFx).
Singleton {
    id: root

    readonly property var styles: ["bars", "wave", "mirror", "ring", "nation", "particles"]
    readonly property var colors: ["auto", "accent", "white", "black"]
    readonly property real aspect: (Quickshell.screens[0]?.width || 16) / (Quickshell.screens[0]?.height || 9)

    // Rows for the editor: numbers get a slider, `values` cycle, bools toggle. `only` limits a row to some styles
    readonly property var kinds: ({
            visualizer: {
                name: "Visualizer",
                icon: "graphic_eq",
                props: { style: "bars", color: "auto", gain: 1, align: "bottom", count: 48, gap: 6, round: 1, fill: "fade", ease: 50, thickness: 2, fillAlpha: 0.45, smooth: 0.55, ringCount: 96, ringWidth: 4, ringSize: 1, ringLine: true, pDensity: 1, pSpeed: 1, pSize: 1, spread: 1 },
                schema: [
                    { key: "style", label: "Style", values: styles },
                    { key: "color", label: "Color", values: colors },
                    { key: "gain", label: "Strength", min: 0.1, max: 2, step: 0.05, unit: "%" },
                    { key: "align", label: "Grows from", values: ["bottom", "top"], only: ["bars", "wave"] },
                    { key: "count", label: "Bars", min: 8, max: 128, step: 1, only: ["bars", "mirror"] },
                    { key: "gap", label: "Gap", min: 0, max: 24, step: 1, unit: "px", only: ["bars", "mirror"] },
                    { key: "round", label: "Rounding", min: 0, max: 1, step: 0.05, unit: "%", only: ["bars", "mirror"] },
                    { key: "fill", label: "Fill", values: ["fade", "solid"], only: ["bars", "mirror"] },
                    { key: "ease", label: "Response", min: 0, max: 200, step: 10, unit: "ms", only: ["bars", "mirror"] },
                    { key: "thickness", label: "Line", min: 0, max: 8, step: 0.5, unit: "px", only: ["wave"] },
                    { key: "fillAlpha", label: "Fill", min: 0, max: 1, step: 0.05, unit: "%", only: ["wave"] },
                    { key: "smooth", label: "Smoothing", min: 0, max: 0.9, step: 0.05, unit: "%", only: ["wave"] },
                    { key: "ringCount", label: "Spikes", min: 24, max: 256, step: 4, only: ["ring"] },
                    { key: "ringWidth", label: "Spike width", min: 1, max: 12, step: 0.5, unit: "px", only: ["ring"] },
                    { key: "ringSize", label: "Hole", min: 0.3, max: 2, step: 0.05, unit: "%", only: ["ring"] },
                    { key: "ringLine", label: "Circle", type: "bool", only: ["ring"] },
                    { key: "spread", label: "Spread", min: 0.3, max: 2.5, step: 0.05, unit: "%", only: ["particles"] },
                    { key: "pDensity", label: "Density", min: 0.25, max: 4, step: 0.05, unit: "%", only: ["particles"] },
                    { key: "pSpeed", label: "Speed", min: 0.25, max: 3, step: 0.05, unit: "%", only: ["particles"] },
                    { key: "pSize", label: "Dot size", min: 0.5, max: 3, step: 0.05, unit: "%", only: ["particles"] }
                ]
            },
            clock: {
                name: "Clock",
                icon: "schedule",
                rect: { w: 0.3, h: 0.2 },
                props: { style: "line", color: "auto", weight: "light", align: "center", seconds: false, card: false, opacity: 1 },
                schema: [
                    { key: "style", label: "Style", values: ["line", "stack", "date"] },
                    { key: "color", label: "Color", values: colors },
                    { key: "weight", label: "Weight", values: ["light", "regular", "bold"] },
                    { key: "align", label: "Align", values: ["left", "center", "right"] },
                    { key: "seconds", label: "Seconds", type: "bool" },
                    { key: "card", label: "Card", type: "bool" },
                    { key: "opacity", label: "Opacity", min: 0.2, max: 1, step: 0.05, unit: "%" }
                ]
            },
            calendar: {
                name: "Calendar",
                icon: "calendar_month",
                rect: { w: 0.18, h: 0.3 },
                props: { color: "auto", card: true, opacity: 1 },
                schema: [
                    { key: "color", label: "Color", values: colors },
                    { key: "card", label: "Card", type: "bool" },
                    { key: "opacity", label: "Opacity", min: 0.2, max: 1, step: 0.05, unit: "%" }
                ]
            },
            media: {
                name: "Now playing",
                icon: "music_note",
                rect: { w: 0.24, h: 0.11 },
                props: { style: "card", color: "auto", card: true, opacity: 1 },
                schema: [
                    { key: "style", label: "Style", values: ["card", "cover", "text"] },
                    { key: "color", label: "Color", values: colors },
                    { key: "card", label: "Card", type: "bool" },
                    { key: "opacity", label: "Opacity", min: 0.2, max: 1, step: 0.05, unit: "%" }
                ]
            },
            weather: {
                name: "Weather",
                icon: "partly_cloudy_day",
                rect: { w: 0.16, h: 0.1 },
                props: { style: "now", color: "auto", card: false, opacity: 1 },
                schema: [
                    { key: "style", label: "Style", values: ["now", "days"] },
                    { key: "color", label: "Color", values: colors },
                    { key: "card", label: "Card", type: "bool" },
                    { key: "opacity", label: "Opacity", min: 0.2, max: 1, step: 0.05, unit: "%" }
                ]
            },
            lyrics: {
                name: "Lyrics",
                icon: "lyrics",
                rect: { w: 0.5, h: 0.14 },
                props: { layout: "lines", effect: ["glow"], lineAnim: "scroll", lineTime: 450, color: "auto", text: "white", size: 22, align: "center", context: 1, fade: 0.6, shrink: 0.75, halo: true, paused: 0.45, opacity: 1, wordAnim: "rise", wordScale: 2.5, wordTime: 320, wordCase: "as is", punct: false },
                schema: [
                    { key: "layout", label: "Layout", values: ["lines", "word"] },
                    { key: "effect", label: "Sung word (mix)", values: ["glow", "fill", "spot", "bounce", "lift", "underline"], multi: true, only: ["lines"] },
                    { key: "lineAnim", label: "Line change", values: ["scroll", "fade", "slide", "rise", "zoom", "blur"], only: ["lines"] },
                    { key: "lineTime", label: "Change speed", min: 150, max: 1200, step: 50, unit: "ms", only: ["lines"] },
                    { key: "wordAnim", label: "Word change", values: ["rise", "fade", "pop", "blur"], only: ["word"] },
                    { key: "wordScale", label: "Word size", min: 1, max: 5, step: 0.1, unit: "%", only: ["word"] },
                    { key: "wordTime", label: "Change speed", min: 80, max: 800, step: 20, unit: "ms", only: ["word"] },
                    { key: "wordCase", label: "Case", values: ["as is", "upper", "lower"], only: ["word"] },
                    { key: "punct", label: "Punctuation", type: "bool", only: ["word"] },
                    { key: "size", label: "Text size", min: 12, max: 72, step: 1, unit: "px" },
                    { key: "color", label: "Sung line", values: colors },
                    { key: "text", label: "Other lines", values: ["white", "black", "accent"] },
                    { key: "align", label: "Align", values: ["left", "center", "right"] },
                    { only: ["lines"], key: "context", label: "Lines around", min: 0, max: 3, step: 1 },
                    { only: ["lines"], key: "fade", label: "Their opacity", min: 0.1, max: 1, step: 0.05, unit: "%" },
                    { only: ["lines"], key: "shrink", label: "Their size", min: 0.4, max: 1, step: 0.05, unit: "%" },
                    { key: "halo", label: "Halo", type: "bool" },
                    { key: "paused", label: "When paused", min: 0, max: 1, step: 0.05, unit: "%" },
                    { key: "opacity", label: "Opacity", min: 0.2, max: 1, step: 0.05, unit: "%" }
                ]
            },
            stats: {
                name: "System",
                icon: "memory",
                rect: { w: 0.2, h: 0.1 },
                props: { style: "rings", color: "auto", card: false, opacity: 1 },
                schema: [
                    { key: "style", label: "Style", values: ["rings", "bars"] },
                    { key: "color", label: "Color", values: colors },
                    { key: "card", label: "Card", type: "bool" },
                    { key: "opacity", label: "Opacity", min: 0.2, max: 1, step: 0.05, unit: "%" }
                ]
            }
        })

    // Effects over the wallpaper, per preset
    readonly property var fxDefaults: ({
            glow: false,
            glowType: "edge",
            glowFrom: "bottom",
            glowSize: 0.45,
            color: "auto",
            blur: false,
            zoom: false,
            shake: false,
            "gain.glow": 1,
            "gain.blur": 1,
            "gain.zoom": 1,
            "gain.shake": 1
        })
    readonly property var fxSchema: [
        { key: "glow", group: "Glow", label: "On", type: "bool" },
        { key: "glowType", group: "Glow", label: "Type", values: ["edge", "radial", "halo"] },
        { key: "glowFrom", group: "Glow", label: "From", values: ["bottom", "top", "left", "right"] },
        { key: "glowSize", group: "Glow", label: "Size", min: 0.1, max: 1, step: 0.05, unit: "%" },
        { key: "gain.glow", group: "Glow", label: "Strength", min: 0.1, max: 2, step: 0.05, unit: "%" },
        { key: "color", group: "Glow", label: "Color", values: colors },
        { key: "blur", group: "Wallpaper", label: "Blur", type: "bool" },
        { key: "gain.blur", group: "Wallpaper", label: "Blur strength", min: 0.1, max: 2, step: 0.05, unit: "%" },
        { key: "zoom", group: "Wallpaper", label: "Zoom", type: "bool" },
        { key: "gain.zoom", group: "Wallpaper", label: "Zoom strength", min: 0.1, max: 2, step: 0.05, unit: "%" },
        { key: "shake", group: "Wallpaper", label: "Shake", type: "bool" },
        { key: "gain.shake", group: "Wallpaper", label: "Shake strength", min: 0.1, max: 2, step: 0.05, unit: "%" }
    ]

    readonly property var presets: adapter.presets
    readonly property var walls: adapter.walls
    readonly property string fallback: adapter.fallback
    // Master switches over every preset: nothing shows, nothing is lost
    readonly property bool widgetsOn: adapter.widgetsOn
    readonly property bool fxOn: adapter.fxOn

    function setWidgetsOn(on) {
        adapter.widgetsOn = on;
    }

    function setFxOn(on) {
        adapter.fxOn = on;
        changed(true);
    }
    // Ordered for menus: as arranged by dragging, presets never moved after them by name
    readonly property var presetIds: {
        const ids = Object.keys(presets);
        const known = adapter.order.filter(id => id in presets);
        return known.concat(ids.filter(id => !known.includes(id)).sort((a, b) => presets[a].name.localeCompare(presets[b].name)));
    }

    function reorder(ids) {
        adapter.order = ids;
    }

    readonly property string currentId: idFor(Wallpaper.current)
    readonly property var current: presets[currentId] ?? null
    readonly property var widgets: current?.widgets ?? []
    // The first visualizer: the popover's style chips and the radial glow follow it
    readonly property var main: widgets.find(w => w.type === "visualizer") ?? null

    // Edit mode (see modules/desk/DeskEditor.qml)
    property bool editing: false
    // The widget the panel edits, and every picked one (Ctrl+click, a band drag) with it
    property string selected: ""
    property var picks: []
    readonly property var selection: picks.filter(id => widgets.some(w => w.id === id))
    // Copied widgets, kept across presets
    property var clip: []
    // The editor's rects while widgets are dragged: { <id>: { x, y, w, h } }, saved on release
    property var preview: null
    // Geometry glides only while this is set: on a wallpaper or preset switch, not while dragging
    property bool morphing: false
    readonly property int morphTime: 800

    property var history: []
    // A run of edits to one setting (a slider drag) is undone as one step
    property string mergeTag: ""
    property var lastEdit: ({ tag: "", at: 0 })

    // An edit landed; `morph` asks the views to glide there instead of jumping
    signal changed(bool morph)

    function idFor(path) {
        const id = path in walls ? walls[path] : fallback;
        return id === "" ? "" : id in presets ? id : fallback;
    }

    function usage(id) {
        let n = 0;
        for (const p in walls)
            if (walls[p] === id)
                n++;
        return n;
    }

    function fxFor(path) {
        const p = presets[idFor(path)];
        const out = Object.assign({}, fxDefaults, p ? p.fx : {});
        if (!p || !fxOn)
            for (const k of ["glow", "blur", "zoom", "shake"])
                out[k] = false;
        const v = (p?.widgets ?? []).find(w => w.type === "visualizer");
        out.cx = v?.x ?? 0.5;
        out.cy = v?.y ?? 0.5;
        return out;
    }

    function uid(prefix) {
        return prefix + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
    }

    function copy(v) {
        return JSON.parse(JSON.stringify(v));
    }

    // Default rect for a visualizer style: strips span the width, round ones are square
    function styleRect(style, x, y) {
        const sq = h => ({ w: h / aspect, h: h });
        switch (style) {
        case "bars":
            return { x: 0.5, y: 0.912, w: 1, h: 0.17 };
        case "wave":
            return { x: 0.5, y: 0.9, w: 1, h: 0.2 };
        case "mirror":
            return Object.assign({ x: 0.5, y: y ?? 0.5 }, { w: 1, h: 0.32 });
        case "particles":
            return { x: x ?? 0.5, y: y ?? 0.5, w: 1, h: 1 };
        default:
            return Object.assign({ x: x ?? 0.5, y: y ?? 0.5 }, sq(0.6));
        }
    }

    function makeWidget(type, extra) {
        const k = kinds[type];
        const rect = type === "visualizer" ? styleRect(extra?.style ?? "bars") : Object.assign({ x: 0.5, y: 0.5 }, k.rect);
        return Object.assign({ id: uid("w"), type: type }, rect, copy(k.props), extra ?? {});
    }

    // Every change goes through here: a copy of the presets is edited, the old one kept for undo
    function edit(fn, morph) {
        const all = copy(presets);
        const tag = mergeTag;
        mergeTag = "";
        if (fn(all) === false)
            return;
        const now = Date.now();
        if (!tag || tag !== lastEdit.tag || now - lastEdit.at > 1500)
            history = history.slice(-49).concat([{ presets: presets, walls: walls, fallback: fallback }]);
        lastEdit = { tag: tag, at: now };
        adapter.presets = all;
        if (morph)
            glide();
        changed(!!morph);
    }

    function undo() {
        const last = history[history.length - 1];
        if (!last)
            return;
        history = history.slice(0, -1);
        lastEdit = { tag: "", at: 0 };
        adapter.presets = last.presets;
        adapter.walls = last.walls;
        adapter.fallback = last.fallback;
        glide();
        changed(true);
    }

    function glide() {
        morphing = true;
        settle.restart();
    }

    // Edits to the preset on screen
    function editCurrent(fn, morph) {
        const id = currentId;
        if (!id)
            return;
        edit(all => fn(all[id]), morph);
    }

    function widget(id) {
        return widgets.find(w => w.id === id) ?? null;
    }

    // add: toggles id in the selection instead of replacing it
    function select(id, add) {
        if (!add)
            picks = id ? [id] : [];
        else if (selection.includes(id))
            picks = selection.filter(x => x !== id);
        else
            picks = selection.concat([id]);
        selected = add && !picks.includes(id) ? (picks[picks.length - 1] ?? "") : id;
    }

    function selectMany(ids, add) {
        picks = add ? selection.concat(ids.filter(id => !selection.includes(id))) : ids;
        selected = picks[picks.length - 1] ?? "";
    }

    function addWidget(type, extra) {
        if (!currentId)
            own(Wallpaper.current, true);
        const w = makeWidget(type, extra);
        if (type !== "visualizer" && extra?.x === undefined)
            Object.assign(w, freeSpot(w));
        editCurrent(p => {
            p.widgets.push(w);
        }, true);
        select(w.id);
        return w.id;
    }

    // First place around the screen where a new widget overlaps nothing; screen-wide visualizers don't count
    function freeSpot(w) {
        const spots = [[0.2, 0.22], [0.8, 0.22], [0.2, 0.7], [0.8, 0.7], [0.5, 0.25], [0.5, 0.62], [0.2, 0.46], [0.8, 0.46]];
        const others = widgets.filter(o => !(o.type === "visualizer" && o.w > 0.9));
        const hits = (x, y) => others.some(o => Math.abs(o.x - x) < (o.w + w.w) / 2 && Math.abs(o.y - y) < (o.h + w.h) / 2);
        const free = spots.find(([x, y]) => !hits(x, y));
        return free ? { x: free[0], y: free[1] } : { x: 0.5, y: 0.5 };
    }

    function setWidget(id, key, value) {
        mergeTag = id + ":" + key;
        editCurrent(p => {
            const w = p.widgets.find(x => x.id === id);
            if (!w)
                return false;
            // A visualizer moving between strip, round and field shapes gets that shape's rect
            if (w.type === "visualizer" && key === "style") {
                const shape = s => s === "bars" || s === "wave" ? "strip" : s;
                const group = s => ["ring", "nation"].includes(s) ? "round" : shape(s);
                if (group(w.style) !== group(value))
                    Object.assign(w, styleRect(value, w.x, w.y));
            }
            w[key] = value;
        }, key === "style");
    }

    // Back to the type's defaults: one setting, or all of them; place and visibility stay
    function resetWidget(id, key) {
        editCurrent(p => {
            const w = p.widgets.find(x => x.id === id);
            if (!w)
                return false;
            const d = kinds[w.type].props;
            for (const k of key ? [key] : Object.keys(d))
                w[k] = copy(d[k]);
        }, !key);
    }

    // { <id>: rect } in one undo step
    function moveWidgets(rects) {
        editCurrent(p => {
            for (const w of p.widgets)
                for (const k of ["x", "y", "w", "h"])
                    if (rects[w.id]?.[k] !== undefined)
                        w[k] = +rects[w.id][k].toFixed(4);
        });
    }

    function removeWidgets(ids) {
        editCurrent(p => {
            p.widgets = p.widgets.filter(w => !ids.includes(w.id));
        }, true);
        select("");
    }

    function copyWidgets(ids) {
        clip = widgets.filter(w => ids.includes(w.id)).map(w => copy(w));
    }

    // Into the preset on screen with new ids; nudged when they'd land right on top of what they were copied from
    function pasteWidgets(list) {
        list = list ?? clip;
        if (!list.length)
            return;
        if (!currentId)
            own(Wallpaper.current, true);
        const over = list.some(c => widgets.some(w => Math.abs(w.x - c.x) < 0.001 && Math.abs(w.y - c.y) < 0.001));
        const added = list.map(c => Object.assign(copy(c), { id: uid("w") }, over ? { x: Math.min(0.95, c.x + 0.03), y: Math.min(0.95, c.y + 0.03) } : {}));
        editCurrent(p => {
            p.widgets = p.widgets.concat(added);
        }, true);
        selectMany(added.map(w => w.id));
    }

    function moveWidget(id, rect) {
        editCurrent(p => {
            const w = p.widgets.find(x => x.id === id);
            if (!w)
                return false;
            for (const k of ["x", "y", "w", "h"])
                if (rect[k] !== undefined)
                    w[k] = +rect[k].toFixed(4);
        });
    }

    function removeWidget(id) {
        editCurrent(p => {
            p.widgets = p.widgets.filter(w => w.id !== id);
        }, true);
        if (selection.includes(id))
            select("");
    }

    function duplicateWidget(id) {
        const src = widget(id);
        if (!src)
            return;
        const w = Object.assign(copy(src), { id: uid("w"), x: Math.min(0.95, src.x + 0.03), y: Math.min(0.95, src.y + 0.03) });
        editCurrent(p => {
            p.widgets.push(w);
        }, true);
        select(w.id);
    }

    // Drawing order: later widgets sit on top
    function restack(id, by) {
        editCurrent(p => {
            const i = p.widgets.findIndex(w => w.id === id), j = i + by;
            if (i < 0 || j < 0 || j >= p.widgets.length)
                return false;
            const [w] = p.widgets.splice(i, 1);
            p.widgets.splice(j, 0, w);
        });
    }

    function setFx(key, value) {
        if (!(key in fxDefaults))
            return;
        mergeTag = "fx:" + key;
        editCurrent(p => {
            p.fx = Object.assign({}, p.fx, { [key]: value });
        });
    }

    // Presets

    function assign(path, id) {
        if (!path)
            return;
        const w = Object.assign({}, walls);
        if (id === null || id === undefined)
            delete w[path];
        else
            w[path] = id;
        history = history.slice(-49).concat([{ presets: presets, walls: walls, fallback: fallback }]);
        lastEdit = { tag: "", at: 0 };
        adapter.walls = w;
        glide();
        changed(true);
    }

    function create(name, from) {
        const id = uid("p");
        const src = from && presets[from] ? copy(presets[from]) : { widgets: [], fx: {} };
        // Fresh widget ids would break the morph between the copy and its source; same ids glide
        edit(all => {
            all[id] = { name: name, widgets: src.widgets, fx: src.fx };
        });
        return id;
    }

    // A copy of the shown preset, named after the wallpaper and assigned to it
    function own(path, quiet) {
        const name = path.split("/").pop().replace(/\.[^.]*$/, "").replace(/[-_]+/g, " ");
        const id = create(name.length > 28 ? name.slice(0, 28) + "…" : name, idFor(path) || null);
        assign(path, id);
        return id;
    }

    function rename(id, name) {
        if (!presets[id] || !name.trim())
            return;
        edit(all => {
            all[id].name = name.trim();
        });
    }

    // The fallback stays; wallpapers that used a removed preset go back to the fallback
    function remove(id) {
        if (id === fallback || !presets[id])
            return;
        const w = Object.assign({}, walls);
        for (const p in w)
            if (w[p] === id)
                delete w[p];
        edit(all => {
            delete all[id];
        }, true);
        adapter.walls = w;
    }

    // "" makes wallpapers without their own preset show nothing
    function setFallback(id) {
        if (id !== "" && !presets[id] || id === fallback)
            return;
        history = history.slice(-49).concat([{ presets: presets, walls: walls, fallback: fallback }]);
        lastEdit = { tag: "", at: 0 };
        adapter.fallback = id;
        glide();
        changed(true);
    }

    // Built-in layouts for a fresh setup; Default is replaced by the old music effect settings if there are any
    function seeds() {
        const vis = (style, extra) => makeWidget("visualizer", Object.assign({ style: style }, extra ?? {}));
        return {
            default: { name: "Default", widgets: [vis("bars")], fx: {} },
            minimal: {
                name: "Minimal",
                widgets: [makeWidget("clock", { x: 0.16, y: 0.2, w: 0.26, h: 0.16, align: "left", style: "date" }), vis("wave", { color: "accent" })],
                fx: { glow: true }
            },
            nation: {
                name: "Nation",
                widgets: [vis("particles"), vis("nation"), makeWidget("clock", { x: 0.5, y: 0.1, w: 0.16, h: 0.08 })],
                fx: { glow: true, glowType: "radial", zoom: true, shake: true }
            }
        };
    }

    // musicfx.json used to hold one visualizer setup, shared, with per-wallpaper overrides
    function migrate(old) {
        const all = seeds();
        const gains = old.gains ?? {};
        const layout = o => {
            const style = o.style ?? "bars", size = o.size ?? 1, x = o.x ?? 0.5, y = o.y ?? 0.5;
            const edge = o.edge ?? "bottom";
            const one = s => {
                const w = makeWidget("visualizer", { style: s, color: o.color ?? "auto", gain: o["gain.desktop"] ?? 1 });
                if (s === "bars" || s === "wave") {
                    const h = (s === "bars" ? 0.17 : 0.2) * size;
                    Object.assign(w, { h: h, y: edge === "top" ? h / 2 + 0.004 : 1 - h / 2 - 0.004, align: edge });
                } else if (s === "mirror") {
                    Object.assign(w, { y: y, h: 0.32 * size });
                } else if (s === "particles") {
                    // The old field covered the screen around its centre and zoomed with the size
                    Object.assign(w, { x: x, y: y, w: 2 * Math.max(x, 1 - x), h: 2 * Math.max(y, 1 - y), spread: size, pDensity: o.pDensity ?? 1, pSpeed: o.pSpeed ?? 1, pSize: o.pSize ?? 1 });
                } else {
                    Object.assign(w, { x: x, y: y, w: 0.6 * size / aspect, h: 0.6 * size });
                }
                return w;
            };
            const fx = {};
            for (const k in fxDefaults)
                if (o[k] !== undefined)
                    fx[k] = o[k];
            return { widgets: (o.layers ?? []).filter(l => l !== style).concat([style]).map(one), fx: fx };
        };
        const base = { style: old.style, layers: old.layers, color: old.color, x: old.x, y: old.y, size: old.size, edge: old.edge,
            pDensity: old.pDensity, pSpeed: old.pSpeed, pSize: old.pSize, "gain.desktop": gains.desktop,
            glow: old.glow, glowType: old.glowType, glowFrom: old.glowFrom, glowSize: old.glowSize, blur: old.blur, zoom: old.zoom, shake: old.shake,
            "gain.glow": gains.glow, "gain.blur": gains.blur, "gain.zoom": gains.zoom, "gain.shake": gains.shake };
        all.default = Object.assign({ name: "Default" }, layout(base));
        const walls = {};
        for (const path in old.walls ?? {}) {
            const id = uid("p");
            const name = path.split("/").pop().replace(/\.[^.]*$/, "");
            all[id] = Object.assign({ name: name.length > 28 ? name.slice(0, 28) + "…" : name }, layout(Object.assign({}, base, old.walls[path])));
            // Same ids as Default where the style matches, so switching between them glides
            all[id].widgets.forEach((w, i) => {
                const twin = all.default.widgets.find(d => d.style === w.style);
                if (twin)
                    w.id = twin.id;
            });
            walls[path] = id;
        }
        adapter.presets = all;
        adapter.walls = walls;
        adapter.fallback = "default";
    }

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            root.glide();
        }
    }

    Timer {
        id: settle
        interval: root.morphTime + 100
        onTriggered: root.morphing = false
    }

    // Leaving edit mode on a wallpaper switch would lose the selection; a switch while editing keeps it
    onEditingChanged: {
        if (!editing)
            select("");
    }

    FileView {
        id: oldFx
        path: Quickshell.statePath("musicfx.json")
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: file

        path: Quickshell.statePath("desk.json")
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            // Lyrics used to be a fixed window shown on every wallpaper
            if (!adapter.lyricsWidget) {
                const all = root.copy(adapter.presets);
                for (const id in all)
                    all[id].widgets.push(root.makeWidget("lyrics", { x: 0.5, y: 0.82 }));
                adapter.presets = all;
                adapter.lyricsWidget = true;
            }
            root.changed(false);
        }
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                return;
            let old = null;
            try {
                old = JSON.parse(oldFx.text());
            } catch (e) {}
            if (old)
                root.migrate(old);
            else
                adapter.presets = root.seeds();
            writeAdapter();
            root.changed(false);
        }

        JsonAdapter {
            id: adapter
            property var presets: ({})
            property var walls: ({})
            property string fallback: "default"
            property var order: []
            property bool widgetsOn: true
            property bool fxOn: true
            property bool lyricsWidget: false
        }
    }

    IpcHandler {
        target: "desk"

        function edit(): void { root.editing = true; }
        function close(): void { root.editing = false; }
        function toggle(): void { root.editing = !root.editing; }
        // Master switches: widgets, effects
        function widgets(): void { root.setWidgetsOn(!root.widgetsOn); }
        function effects(): void { root.setFxOn(!root.fxOn); }
        function undo(): void { root.undo(); }
        // Preset id or name for the current wallpaper; "" for none, "fallback" to drop the assignment
        function preset(name: string): void {
            if (name === "fallback")
                return root.assign(Wallpaper.current, null);
            const id = name in root.presets ? name : Object.keys(root.presets).find(k => root.presets[k].name === name);
            root.assign(Wallpaper.current, name === "" ? "" : id ?? root.fallback);
        }
        // A widget of that type in the shown preset
        function add(type: string): string {
            return type in root.kinds ? root.addWidget(type) : "";
        }
        // A copy of the shown preset for this wallpaper only
        function own(): string {
            return root.own(Wallpaper.current);
        }
        function remove(id: string): void {
            root.remove(id);
        }
        function list(): string {
            return root.presetIds.map(id => `${id}\t${root.presets[id].name}\t${root.usage(id)}${id === root.fallback ? "\tfallback" : ""}`).join("\n");
        }
        function current(): string {
            return JSON.stringify({ id: root.currentId, preset: root.current });
        }
    }
}
