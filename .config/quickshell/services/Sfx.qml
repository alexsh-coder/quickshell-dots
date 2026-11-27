pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland

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
        shot: 0.45
    })

    property var last: ({})

    // gap: ms the same sound stays quiet after playing, so drags and fast moves don't machine-gun
    function play(name, gap) {
        if (!on || (name === "hover" && !Settings.sfxHover))
            return;
        const now = Date.now();
        if ((gap ?? 40) > 0 && now - (last[name] ?? 0) < (gap ?? 40))
            return;
        last[name] = now;
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

    Component {
        id: effect
        SoundEffect {
            property string name
            source: root.dir + root.pack + "/" + name + ".wav"
            volume: root.map[name] * Settings.sfxVolume
        }
    }
}
