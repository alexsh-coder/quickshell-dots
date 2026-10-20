pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Music-reactive effect settings, persisted between sessions
Singleton {
    id: root

    readonly property var styles: ["bars", "wave", "mirror", "ring", "nation", "flow"]

    property alias intensity: adapter.intensity
    property alias desktop: adapter.desktop
    property alias style: adapter.style
    property alias lyrics: adapter.lyrics
    property alias glow: adapter.glow
    property alias zoom: adapter.zoom
    property alias shake: adapter.shake
    property alias blur: adapter.blur

    readonly property bool wallpaperFx: zoom || shake || glow || blur

    // Per-effect strength on top of the global intensity, 1 = default
    function gain(key) {
        return adapter.gains[key] ?? 1;
    }

    function setGain(key, v) {
        const g = Object.assign({}, adapter.gains);
        g[key] = Math.round(Math.max(0.1, Math.min(2, v)) * 20) / 20;
        adapter.gains = g;
    }

    function setIntensity(v) {
        adapter.intensity = Math.round(Math.max(0.25, Math.min(2, v)) * 20) / 20;
    }

    FileView {
        path: Quickshell.statePath("musicfx.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property real intensity: 1
            property bool desktop: false
            property string style: "bars"
            property bool lyrics: true
            property bool glow: false
            property bool zoom: false
            property bool shake: false
            property bool blur: false
            property var gains: ({})
        }
    }

    IpcHandler {
        target: "musicfx"

        function toggle(name: string): void {
            if (["desktop", "lyrics", "glow", "zoom", "shake", "blur"].includes(name))
                adapter[name] = !adapter[name];
        }
        function style(name: string): void {
            if (root.styles.includes(name))
                adapter.style = name;
        }
        function intensity(value: real): void {
            root.setIntensity(value);
        }
        function strength(name: string, value: real): void {
            if (["desktop", "glow", "zoom", "shake", "blur"].includes(name))
                root.setGain(name, value);
        }
    }
}
