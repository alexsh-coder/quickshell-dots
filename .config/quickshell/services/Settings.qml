pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// What the settings window changes. The shell's own choices are read from here; Hyprland's are
// written to hypr/settings.lua, which hyprland.lua reads, and applied with a reload
Singleton {
    id: root

    // The settings window is up
    property bool open: false

    property alias transition: adapter.transition
    property alias transitionTime: adapter.transitionTime
    property alias transitionFrom: adapter.transitionFrom
    property alias clickToChange: adapter.clickToChange
    // Styles left out of "random" and "random-glitch"
    readonly property var randomSkip: adapter.randomSkip
    readonly property var glitchSkip: adapter.glitchSkip
    // Own lengths of some styles, ms; the rest take transitionTime
    readonly property var durations: adapter.durations
    property alias slideshow: adapter.slideshow
    property alias panelScale: adapter.panelScale
    property alias nightTemp: adapter.nightTemp
    property alias ecoOnBattery: adapter.ecoOnBattery
    readonly property var hypr: adapter.hypr
    readonly property var monitors: adapter.monitors

    // Battery saver: blur and shadows off while unplugged
    readonly property bool eco: ecoOnBattery && UPower.onBattery
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false

    // Hyprland's own values, which hyprland.lua keeps for anything not set here
    readonly property var hyprDefaults: ({
        gaps_in: 5,
        gaps_out: 20,
        border_size: 2,
        rounding: 10,
        inactive_opacity: 1,
        blur: true,
        shadows: true,
        animations: true,
        anim_speed: 1,
        window_style: "",
        workspace_style: "",
        repeat_rate: 25,
        repeat_delay: 600,
        mouse_sensitivity: 0,
        natural_scroll: true,
        tap_to_click: true,
        cursor_size: 28
    })

    readonly property string luaPath: Quickshell.env("HOME") + "/.config/hypr/settings.lua"

    function get(key) {
        return adapter.hypr[key] ?? hyprDefaults[key];
    }

    function set(key, value) {
        const all = Object.assign({}, adapter.hypr);
        if (value === hyprDefaults[key])
            delete all[key];
        else
            all[key] = value;
        adapter.hypr = all;
        if (key === "cursor_size")
            Quickshell.execDetached(["hyprctl", "setcursor", Quickshell.env("XCURSOR_THEME") || "default", String(value)]);
    }

    function durationOf(name) {
        return adapter.durations[name] ?? adapter.transitionTime;
    }

    // ms, or null back to the default
    function setDuration(name, ms) {
        const all = Object.assign({}, adapter.durations);
        if (ms === null)
            delete all[name];
        else
            all[name] = ms;
        adapter.durations = all;
    }

    // Puts a style in or out of its group's random pick
    function toggleRandom(glitch, name) {
        const skip = (glitch ? adapter.glitchSkip : adapter.randomSkip).slice();
        const i = skip.indexOf(name);
        if (i >= 0)
            skip.splice(i, 1);
        else
            skip.push(name);
        if (glitch)
            adapter.glitchSkip = skip;
        else
            adapter.randomSkip = skip;
    }

    // A monitor's mode ("3840x2160@60.00"), scale and VRR, kept once a change is confirmed
    function setMonitor(name, m) {
        const all = Object.assign({}, adapter.monitors);
        all[name] = m;
        adapter.monitors = all;
    }

    function lua(v) {
        if (typeof v === "string")
            return JSON.stringify(v);
        if (typeof v === "object") {
            const keys = Object.keys(v).sort();
            return "{ " + keys.map(k => "[" + JSON.stringify(k) + "] = " + lua(v[k])).join(", ") + " }";
        }
        return String(v);
    }

    function luaText() {
        const lines = ["-- Written by Quickshell's settings window (services/Settings.qml); edits here get replaced.", "return {"];
        const all = Object.assign({}, adapter.hypr);
        if (Object.keys(adapter.monitors).length)
            all.monitors = adapter.monitors;
        if (adapter.panelScale !== 1)
            all.panel_scale = adapter.panelScale;
        if (eco)
            all.eco = true;
        for (const k of Object.keys(all).sort())
            lines.push("    " + k + " = " + lua(all[k]) + ",");
        lines.push("}");
        return lines.join("\n") + "\n";
    }

    function sync() {
        if (!file.loaded || !luaFile.ready)
            return;
        const text = luaText();
        if (text === luaFile.text())
            return;
        luaFile.setText(text);
    }

    onEcoChanged: sync()

    // Sliders change things many times a second: one reload once they settle
    Timer {
        id: debounce
        interval: 250
        onTriggered: root.sync()
    }

    // Restarts the shell the way Hyprland starts it, at the panel scale set now
    function restartShell() {
        Quickshell.execDetached(["setsid", "-f", Quickshell.shellDir + "/scripts/restart.sh", String(Quickshell.processId), String(adapter.panelScale)]);
    }

    FileView {
        id: luaFile

        property bool ready: false

        path: root.luaPath
        printErrors: false
        onLoaded: {
            ready = true;
            root.sync();
        }
        onLoadFailed: {
            ready = true;
            root.sync();
        }
        onSaved: Quickshell.execDetached(["hyprctl", "reload"])
    }

    FileView {
        id: file

        property bool loaded: false

        path: Quickshell.statePath("settings.json")
        onAdapterUpdated: {
            writeAdapter();
            debounce.restart();
        }
        onLoaded: {
            loaded = true;
            root.sync();
        }
        onLoadFailed: err => {
            loaded = true;
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property string transition: "circle"
            property int transitionTime: 800
            // "edge", or "cursor" to start where the pointer is
            property string transitionFrom: "edge"
            // With "cursor": a click on the empty desktop switches to a random wallpaper
            property bool clickToChange: false
            property var randomSkip: []
            property var glitchSkip: []
            property var durations: ({})
            // Minutes between random wallpapers, 0 for off
            property int slideshow: 0
            property real panelScale: 1
            property int nightTemp: 4000
            property bool ecoOnBattery: false
            // Hyprland options by their settings.lua names; only those changed from hyprDefaults
            property var hypr: ({})
            property var monitors: ({})
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.open = !root.open;
        }
        function open(): void {
            root.open = true;
        }
        function close(): void {
            root.open = false;
        }
        function transition(name: string): void {
            adapter.transition = name;
        }
        // "edge" or "cursor"
        function from(where: string): void {
            adapter.transitionFrom = where;
        }
        // A Hyprland option by its settings.lua name; value is JSON ("12", "true", "\"slide\"")
        function hypr(key: string, value: string): void {
            if (key in root.hyprDefaults)
                root.set(key, JSON.parse(value));
        }
    }
}
