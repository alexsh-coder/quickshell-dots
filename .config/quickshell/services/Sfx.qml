pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Interface sounds (Kenney, CC0), preloaded so they start without a gap
Singleton {
    id: root

    readonly property bool on: Settings.sfx
    readonly property string dir: Qt.resolvedUrl("../sounds/")

    readonly property var packs: [
        { value: "glass", label: "Glass" },
        { value: "clicky", label: "Clicky" },
        { value: "digital", label: "Digital" },
        { value: "scifi", label: "Sci-fi" },
        { value: "casino", label: "Casino" },
        { value: "paper", label: "Paper" }
    ]
    readonly property string pack: packs.some(p => p.value === Settings.sfxPack) ? Settings.sfxPack : "glass"

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
        const e = effects.find(e => e.name === name);
        if (!e)
            return;
        e.stop();
        e.play();
    }

    readonly property var effects: names.map(n => effect.createObject(root, { name: n }))
    readonly property var names: Object.keys(map)

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
    readonly property bool canType: typingPanels.length > 0
        || (!!Hyprland.activeToplevel && Hyprland.activeToplevel.workspace === Hyprland.focusedWorkspace)

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
        SoundEffect {
            property string name
            source: root.dir + root.pack + "/" + name + ".wav"
            volume: root.map[name] * Settings.sfxVolume
        }
    }
}
