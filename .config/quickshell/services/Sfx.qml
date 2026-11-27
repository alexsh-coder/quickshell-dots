pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Interface sounds (Kenney, CC0), preloaded so they start without a gap
Singleton {
    id: root

    readonly property bool on: Settings.sfx && !(Settings.sfxMuteMusic && Players.music.some(p => p.isPlaying))
    readonly property string dir: Qt.resolvedUrl("../sounds/")

    readonly property var packs: [
        { value: "glass", label: "Glass", library: "interface-sounds" },
        { value: "clicky", label: "Clicky", library: "ui-audio" },
        { value: "digital", label: "Digital", library: "digital-audio" },
        { value: "scifi", label: "Sci-fi", library: "sci-fi-sounds" },
        { value: "casino", label: "Casino", library: "casino-audio" },
        { value: "paper", label: "Paper", library: "rpg-audio" }
    ]
    readonly property string pack: packs.some(p => p.value === Settings.sfxPack) ? Settings.sfxPack : "glass"

    // Every sound of the Kenney pack a preset was made from, to swap single events for
    readonly property string library: packs.find(p => p.value === pack).library
    readonly property var choices: libraryIndex[library] ?? []
    property var libraryIndex: ({})
    FileView {
        id: indexFile
        path: Quickshell.shellDir + "/sounds/library/index.json"
        onLoaded: root.libraryIndex = JSON.parse(text())
        // A hot reload hands the file back already read, with no onLoaded
        Component.onCompleted: {
            waitForJob();
            if (text().length)
                root.libraryIndex = JSON.parse(text());
        }
    }

    // Library sounds picked for an event; several play in turns at random
    // Which library sound each preset event was cut from, for its name in settings
    property var presetIndex: ({})
    FileView {
        path: Quickshell.shellDir + "/sounds/presets.json"
        onLoaded: root.presetIndex = JSON.parse(text())
        Component.onCompleted: {
            waitForJob();
            if (text().length)
                root.presetIndex = JSON.parse(text());
        }
    }

    function presetName(name) {
        return (presetIndex[pack]?.[name] ?? "").replace(/[_-]/g, " ");
    }

    function picked(name) {
        const v = Settings.sfxPick[pack + "/" + name];
        // Read back from settings.json a list is not a plain JS array
        const list = !v ? [] : typeof v === "string" ? [v] : Array.from(v);
        return list.filter(c => choices.includes(c));
    }

    // Adds or removes one; "" goes back to the preset's own
    function pick(name, sound) {
        const all = Object.assign({}, Settings.sfxPick);
        const now = picked(name);
        const next = !sound ? [] : now.includes(sound) ? now.filter(c => c !== sound) : now.concat(sound);
        if (next.length)
            all[pack + "/" + name] = next;
        else
            delete all[pack + "/" + name];
        Settings.sfxPick = all;
    }

    function fileOf(name, sound) {
        return sound ? dir + "library/" + library + "/" + sound + ".wav" : dir + pack + "/" + name + ".wav";
    }

    function filesOf(name) {
        const p = picked(name);
        return p.length ? p.map(c => fileOf(name, c)) : [fileOf(name, "")];
    }

    // One of the event's sounds at random, never the one it played last time
    property var lastFile: ({})
    function nextFile(name) {
        const files = filesOf(name);
        const rest = files.length > 1 ? files.filter(f => f !== lastFile[name]) : files;
        const f = rest[Math.floor(Math.random() * rest.length)];
        lastFile[name] = f;
        return f;
    }

    // Loaded sound per file, made ahead so the first play has no gap
    property var pool: ({})
    function effectFor(file) {
        if (!pool[file])
            pool[file] = effect.createObject(root, { source: file });
        return pool[file];
    }

    function preload() {
        for (const n of Object.keys(map))
            for (const f of filesOf(n))
                effectFor(f);
    }

    onPackChanged: Qt.callLater(preload)
    onChoicesChanged: Qt.callLater(preload)
    Connections {
        target: Settings
        function onSfxPickChanged() {
            Qt.callLater(root.preload);
        }
    }
    Component.onCompleted: preload()

    function audition(name, sound) {
        tryOut.volume = map[name] * Settings.sfxVolume;
        const src = sound === undefined ? nextFile(name) : fileOf(name, sound);
        tryOut.stop();
        if (tryOut.source.toString() !== src)
            tryOut.source = src;
        tryOut.play();
    }

    SoundEffect {
        id: tryOut
    }

    // Every pack has sounds/<pack>/<name>.wav, peak-normalized; the gain sets how loud each event is
    readonly property var map: ({
        hover: 0.18,
        click: 0.45,
        toggleOn: 0.4,
        toggleOff: 0.4,
        open: 0.35,
        close: 0.3,
        popOpen: 0.35,
        popSwitch: 0.22,
        popClose: 0.25,
        hoverPop: 0.15,
        clickPop: 0.4,
        slide: 0.2,
        workspace: 0.3,
        winOpen: 0.3,
        winClose: 0.28,
        notify: 0.5,
        urgent: 0.6,
        error: 0.5,
        lock: 0.4,
        unlock: 0.45,
        shot: 0.45,
        type: 0.25,
        typeBig: 0.3,
        typeEnter: 0.35,
        osdVolume: 0.35,
        osdBright: 0.3,
        osdOn: 0.4,
        osdOff: 0.4,
        osdText: 0.35
    })

    readonly property var eventLabels: ({
        hover: "Hover", hoverPop: "Hover in popouts", slide: "Slider tick",
        click: "Click", clickPop: "Click in popouts", toggleOn: "Switch on", toggleOff: "Switch off",
        open: "Open", close: "Close",
        popOpen: "Open", popSwitch: "Switch to another", popClose: "Close",
        winOpen: "Window opens", winClose: "Window closes",
        workspace: "Switch",
        notify: "Notification", urgent: "Urgent notification",
        osdVolume: "Volume", osdBright: "Brightness", osdOn: "Turned on", osdOff: "Turned off", osdText: "Layout and text",
        type: "Key", typeBig: "Space, Backspace, Tab", typeEnter: "Enter",
        lock: "Lock", unlock: "Unlock", error: "Wrong password",
        shot: "Shutter"
    })

    // What can be switched off on its own in settings, and the events each one covers
    readonly property var groups: [
        { id: "hover", label: "Hover", hint: "Moving over buttons, list rows and bar items", events: ["hover", "hoverPop", "slide"], sample: "hover" },
        { id: "clicks", label: "Clicks and switches", hint: "Buttons, chips, toggles, sliders", events: ["click", "clickPop", "toggleOn", "toggleOff"], sample: "click" },
        { id: "panels", label: "Panels", hint: "Launcher, overview, settings, menus opening and closing", events: ["open", "close"], sample: "open" },
        { id: "popouts", label: "Bar popouts", hint: "Media, volume, power and the rest under the bar", events: ["popOpen", "popSwitch", "popClose"], sample: "popOpen" },
        { id: "windows", label: "Windows", hint: "An app window opening or closing", events: ["winOpen", "winClose"], sample: "winOpen" },
        { id: "workspaces", label: "Workspaces", hint: "Switching to another workspace", events: ["workspace"], sample: "workspace" },
        { id: "notifications", label: "Notifications", hint: "A popup arriving; quiet under Do not disturb", events: ["notify", "urgent"], sample: "notify" },
        { id: "osd", label: "On-screen display", hint: "Volume, brightness, mute, layout, caps and toggles from keys", events: ["osdVolume", "osdBright", "osdOn", "osdOff", "osdText"], sample: "osdVolume" },
        { id: "typing", label: "Typing", hint: "Typing keys in any window; shortcuts, arrows and F-keys stay quiet", events: ["type", "typeBig", "typeEnter"], sample: "type" },
        { id: "lock", label: "Lock screen", hint: "Locking, unlocking, a wrong password", events: ["lock", "unlock", "error"], sample: "lock" },
        { id: "screenshot", label: "Screenshot", hint: "A region or window shot", events: ["shot"], sample: "shot" }
    ]
    readonly property var groupOf: {
        const out = {};
        for (const g of groups)
            for (const e of g.events)
                out[e] = g.id;
        return out;
    }

    function enabled(group) {
        return !Settings.sfxOff.includes(group);
    }

    function setEnabled(group, on) {
        const rest = Settings.sfxOff.filter(g => g !== group);
        Settings.sfxOff = on ? rest : rest.concat(group);
    }

    property var last: ({})
    // Counts sounds of something happening, so a click can stand down when its press already made one
    property int actions: 0
    readonly property var passive: ["hover", "hoverPop", "slide", "click", "clickPop", "type", "typeBig", "typeEnter"]

    // A click that plays only if what it did (opened, closed, switched something) made no sound of its own
    function tap(name) {
        const seen = actions;
        Qt.callLater(() => {
            if (actions === seen)
                play(name);
        });
    }

    // gap: ms the same sound stays quiet after playing, so drags and fast moves don't machine-gun
    function play(name, gap) {
        if (!on || !enabled(groupOf[name]))
            return;
        const now = Date.now();
        // Typing reshuffles lists (launcher results), which would tick on every key
        if (name === "hover" && now - Math.max(last.type ?? 0, last.typeBig ?? 0, last.typeEnter ?? 0) < 250)
            return;
        // A dragged slider already ticks; the OSD it sets off stays quiet
        if ((name === "osdVolume" || name === "osdBright") && now - (last.slide ?? 0) < 200)
            return;
        if ((gap ?? 40) > 0 && now - (last[name] ?? 0) < (gap ?? 40))
            return;
        last[name] = now;
        if (!passive.includes(name))
            actions++;
        if (map[name] === undefined)
            return;
        const e = effectFor(nextFile(name));
        e.volume = map[name] * Settings.sfxVolume;
        e.stop();
        e.play();
    }


    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow")
                root.play("winOpen", 120);
            else if (event.name === "closewindow")
                root.play("winClose", 120);
        }
    }

    // Shell panels taking text right now (launcher, clipboard, lock), by name
    property var typingPanels: []
    function typingIn(panel, on) {
        const rest = typingPanels.filter(p => p !== panel);
        typingPanels = on ? rest.concat(panel) : rest;
    }
    // Keys only count as typing with somewhere to type into: a window on the focused workspace, or a shell panel
    readonly property bool canType: !!(typingPanels.length > 0
        || (Hyprland.activeToplevel && Hyprland.activeToplevel.workspace === Hyprland.focusedWorkspace))

    // Key presses from any keyboard; only whether it was a big key comes through
    Process {
        running: root.on && root.enabled("typing")
        command: ["python3", Quickshell.shellDir + "/scripts/keytap.py"]
        stdout: SplitParser {
            onRead: line => {
                if (!root.canType)
                    return;
                for (const c of line)
                    root.play(c === "e" ? "typeEnter" : c === "b" ? "typeBig" : "type", 0);
            }
        }
    }

    Component {
        id: effect
        SoundEffect {}
    }
}
