pragma Singleton

import QtQuick
import Quickshell

// Drives the wallpaper effects in shaders/wallfx.frag: a flash and rings from the visualizer on kicks,
// bloom breathing with the bass, VHS growing with loudness, hue drifting and jumping on kicks
Singleton {
    id: root

    readonly property bool on: (MusicFx.pulse || MusicFx.ripple || MusicFx.bloom || MusicFx.vhs || MusicFx.hue) && Cava.active

    // Kick relative to the recent loudest one, so quiet tracks hit as hard
    property real hit: 0
    property real peak: 0.05
    property real lastKick: 0
    property real since: 1
    property real time: 0

    readonly property real pulse: MusicFx.pulse ? Math.pow(Math.max(0, hit - 0.3) / 0.7, 2) * MusicFx.gain("pulse") * MusicFx.fade : 0
    // Bass relative to its recent peak, so a quiet mix swells as much as a loud one
    property real bassPeak: 0.15
    readonly property real swellBass: Math.pow(Math.min(1, Cava.bass / bassPeak), 2)
    readonly property real bloom: MusicFx.bloom ? (0.15 + swellBass * 1.6) * MusicFx.gain("bloom") * MusicFx.fade : 0
    // Saturation and contrast swell with it, each with its own amount
    readonly property real swell: MusicFx.bloom ? (0.1 + swellBass * 0.9) * MusicFx.fade : 0
    readonly property real sat: swell * 0.5 * MusicFx.value("bloomSat")
    readonly property real contrast: swell * MusicFx.value("bloomContrast")
    readonly property real vhs: MusicFx.vhs ? (0.35 + Math.min(1, Cava.level * 2) * 0.65) * MusicFx.gain("vhs") * MusicFx.fade : 0

    property real hueDrift: 0
    property real hueKick: 0
    property real hueTarget: 0
    readonly property real hue: hueDrift + hueKick
    readonly property real hueMix: MusicFx.hue ? MusicFx.fade : 0
    // The same for the accent of the widgets and the glow (Theme.hueShift), which outlive the music
    property real tint: on && MusicFx.hue ? MusicFx.fade : 0
    Behavior on tint { NumberAnimation { duration: 600; easing.type: Easing.InOutSine } }

    // Up to four rings at once: seconds since each started (-1 = free) and its push in px
    property var waveAges: [-1, -1, -1, -1]
    property var waveAmps: [0, 0, 0, 0]
    property int slot: 0
    readonly property vector4d ages: Qt.vector4d(waveAges[0], waveAges[1], waveAges[2], waveAges[3])
    readonly property vector4d amps: MusicFx.ripple ? Qt.vector4d(waveAmps[0], waveAmps[1], waveAmps[2], waveAmps[3]).times(MusicFx.fade) : Qt.vector4d(0, 0, 0, 0)

    function onset(strength) {
        since = 0;
        if (MusicFx.ripple) {
            const a = waveAges.slice(), p = waveAmps.slice();
            a[slot] = 0;
            p[slot] = (10 + strength * 14) * MusicFx.gain("ripple");
            waveAges = a;
            waveAmps = p;
            slot = (slot + 1) % 4;
        }
        if (MusicFx.hue)
            hueTarget += (0.25 + strength * 0.35) * MusicFx.gain("hue");
    }

    Connections {
        target: Cava
        enabled: root.on

        function onKickChanged() {
            const k = Cava.kick;
            root.peak = Math.max(root.peak * 0.995, k, 0.05);
            root.hit = Math.min(1, k / root.peak);
            if (k - root.lastKick > 0.03 && k > root.peak * 0.6 && root.since > 0.25)
                root.onset(k / root.peak);
            root.lastKick = k;
        }
    }

    onOnChanged: {
        if (!on) {
            hit = 0;
            waveAges = [-1, -1, -1, -1];
        }
    }

    FrameAnimation {
        running: root.on
        onTriggered: {
            const dt = frameTime;
            root.time += dt;
            root.since += dt;
            // Falls by half in about 6 s
            root.bassPeak = Math.max(root.bassPeak * Math.pow(0.5, dt / 6), Cava.bass, 0.15);
            if (root.waveAges.some(a => a >= 0))
                root.waveAges = root.waveAges.map(a => a < 0 || a + dt > 1.4 ? -1 : a + dt);
            if (MusicFx.hue) {
                root.hueDrift = (root.hueDrift + dt * 0.12 * MusicFx.gain("hue")) % (Math.PI * 2);
                root.hueKick += (root.hueTarget - root.hueKick) * Math.min(1, dt * 5);
                if (root.hueKick > Math.PI * 2) {
                    root.hueKick -= Math.PI * 2;
                    root.hueTarget -= Math.PI * 2;
                }
            }
        }
    }
}
