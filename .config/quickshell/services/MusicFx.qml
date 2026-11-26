pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Music-reactive effects. Intensity, lyrics and the visualizer switch are global; the effects over the
// wallpaper (glow, blur, zoom, shake and the rest) come with the desktop preset (see Desk). Switching wallpapers,
// numbers glide to the new values; if a type changes, the effects fade out, swap and fade back in,
// in step with the wallpaper transition.
Singleton {
    id: root

    readonly property var styles: Desk.styles

    property alias intensity: adapter.intensity
    property alias lyrics: adapter.lyrics
    // Master switch for every visualizer widget
    readonly property bool desktop: adapter.desktop

    readonly property bool glow: value("glow")
    readonly property string glowType: value("glowType")
    readonly property string glowFrom: value("glowFrom")
    readonly property real glowSize: value("glowSize")
    readonly property string color: value("color")
    readonly property bool blur: value("blur")
    readonly property bool zoom: value("zoom")
    readonly property bool shake: value("shake")
    readonly property bool glitch: value("glitch")
    readonly property var glitchTargets: value("glitchTargets") ?? []
    readonly property bool glitchDrift: value("glitchDrift")
    // How the wallpaper tears, glitch.frag's `variant`
    readonly property var glitchStyles: ["wide", "soft", "sparse", "thin", "clean", "gentle", "edges"]
    readonly property string glitchStyle: value("glitchStyle") ?? "wide"
    readonly property bool pulse: value("pulse")
    readonly property bool ripple: value("ripple")
    readonly property bool bloom: value("bloom")
    readonly property bool vhs: value("vhs")
    readonly property bool hue: value("hue")
    readonly property bool rgb: value("rgb")
    // Centre of the radial glow: the preset's first visualizer
    readonly property real x: value("cx")
    readonly property real y: value("cy")

    readonly property var wallpaperKeys: ["glow", "blur", "zoom", "shake", "glitch", "pulse", "ripple", "bloom", "vhs", "hue", "rgb"]
    readonly property bool wallpaperFx: wallpaperKeys.some(k => root[k])

    // The transition between two wallpapers' settings
    property var from: Desk.fxFor("")
    property var to: from
    property real t: 1
    property bool swapping: false
    // Multiplies the opacity of every effect: dips to 0 halfway through a swap
    readonly property real fade: swapping ? Math.abs(1 - 2 * t) : 1

    function value(k) {
        const a = from[k], b = to[k];
        if (t >= 1 || a === undefined)
            return b;
        if (typeof a === "number" && typeof b === "number")
            return a + (b - a) * t;
        return t < 0.5 ? a : b;
    }

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function transition() {
        const now = {};
        for (const k in to)
            now[k] = value(k);
        const next = Desk.fxFor(Wallpaper.current);
        if (same(now, next))
            return;
        swapping = Object.keys(next).some(k => typeof next[k] !== "number" && !same(now[k], next[k]));
        from = now;
        to = next;
        t = 0;
        anim.restart();
    }

    // After an edit: straight to the result
    function refresh() {
        anim.stop();
        to = Desk.fxFor(Wallpaper.current);
        from = to;
        t = 1;
        swapping = false;
    }

    function set(k, v) {
        if (k === "desktop")
            adapter.desktop = v;
        else
            Desk.setFx(k, v);
    }

    // Per-effect strength on top of the global intensity, 1 = default; "desktop" is the main visualizer's
    function gain(key) {
        if (key === "desktop")
            return Desk.main?.gain ?? 1;
        return value("gain." + key) ?? 1;
    }

    function setGain(key, v) {
        v = Math.round(Math.max(0.1, Math.min(2, v)) * 20) / 20;
        if (key === "desktop") {
            if (Desk.main)
                Desk.setWidget(Desk.main.id, "gain", v);
        } else {
            Desk.setFx("gain." + key, v);
        }
    }

    // The popover's style chips: the main visualizer takes the style, or one is added
    function setStyle(name) {
        adapter.desktop = true;
        const twin = Desk.widgets.find(w => w.type === "visualizer" && w.style === name && w !== Desk.main);
        if (twin)
            Desk.removeWidget(twin.id);
        if (Desk.main)
            Desk.setWidget(Desk.main.id, "style", name);
        else
            Desk.addWidget("visualizer", { style: name });
    }

    // Extra visualizers of a style, on top of the main one
    function toggleLayer(name) {
        const extra = Desk.widgets.find(w => w.type === "visualizer" && w.style === name && w !== Desk.main);
        if (extra)
            Desk.removeWidget(extra.id);
        else
            Desk.addWidget("visualizer", { style: name });
    }

    function hasLayer(name) {
        return Desk.widgets.some(w => w.type === "visualizer" && w.style === name && w !== Desk.main);
    }

    // Master switch: off remembers which effects were on, on brings them back (the classic ones if none were)
    function setWallpaperFx(on) {
        const values = {};
        if (on) {
            const restore = adapter.savedFx.length ? adapter.savedFx : wallpaperKeys.slice(0, 5);
            wallpaperKeys.forEach(k => values[k] = restore.includes(k));
        } else {
            adapter.savedFx = wallpaperKeys.filter(k => root[k]);
            wallpaperKeys.forEach(k => values[k] = false);
        }
        Desk.setFxMany(values);
    }

    function setIntensity(v) {
        adapter.intensity = Math.round(Math.max(0.25, Math.min(2, v)) * 20) / 20;
    }

    // Matches the awww transition
    NumberAnimation {
        id: anim
        target: root
        property: "t"
        from: 0
        to: 1
        duration: Desk.morphTime
        easing.type: Easing.InOutSine
        onFinished: root.swapping = false
    }

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            root.transition();
        }
    }

    Connections {
        target: Desk
        function onChanged(morph) {
            morph ? root.transition() : root.refresh();
        }
    }

    FileView {
        id: file

        path: Quickshell.statePath("musicfx.json")
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property real intensity: 1
            property bool desktop: true
            property bool lyrics: true
            property list<string> savedFx: []
        }
    }

    IpcHandler {
        target: "musicfx"

        function toggle(name: string): void {
            if (name === "lyrics")
                adapter.lyrics = !adapter.lyrics;
            else if (name === "desktop")
                adapter.desktop = !adapter.desktop;
            else if (root.wallpaperKeys.includes(name))
                Desk.setFx(name, !root[name]);
            else if (name === "wallpaper")
                root.setWallpaperFx(!root.wallpaperFx);
        }
        function style(name: string): void {
            if (root.styles.includes(name))
                root.setStyle(name);
        }
        function layer(name: string): void {
            if (root.styles.includes(name))
                root.toggleLayer(name);
        }
        function intensity(value: real): void {
            root.setIntensity(value);
        }
        // value is JSON ("true", "0.3", "\"edge\"")
        function set(key: string, value: string): void {
            try {
                root.set(key, JSON.parse(value));
            } catch (e) {}
        }
        function strength(name: string, value: real): void {
            if (["desktop", ...root.wallpaperKeys].includes(name))
                root.setGain(name, value);
        }
    }
}
