pragma Singleton

import QtQuick
import Quickshell

// Drives the glitch effect (shaders/glitch.frag): the colour channels drift apart with the bass, and a kick
// sets off a short burst of torn strips on one target at a time (the wallpaper, a visualizer, the lyrics),
// or on all of them when it hits hard
Singleton {
    id: root

    readonly property bool on: MusicFx.glitch && Cava.active
    readonly property real gain: MusicFx.gain("glitch")
    // Steady RGB drift in px
    readonly property real split: on && MusicFx.glitchDrift ? Math.min(6, Cava.bass * 4 * gain) * MusicFx.fade : 0

    property string target: ""
    property string last: ""
    property real burst: 0
    property real seed: 0

    property real lastKick: 0
    property real peak: 0.05
    property real since: 1
    property real reseed: 0
    property real duration: 0.2
    // Integer part of the seed: which burst this is, so the shader keeps one look per burst
    property int burstId: 0
    property real level: 0
    property real life: 0
    // Kicks since the last burst, and a second hit queued after a hard one
    property int beats: 0
    property real echo: -1

    function has(t) {
        return on && MusicFx.glitchTargets.includes(t);
    }

    // 0..1 for one target
    function burstFor(t) {
        return target === "all" || target === t ? burst * MusicFx.fade : 0;
    }

    // Targets that would show it right now
    function candidates() {
        const shown = type => Desk.widgetsOn && Desk.widgets.some(w => w.type === type && !w.hidden);
        return ["wall", "ring", "lyrics"].filter(t => has(t) && (t === "wall" ? !Wallpaper.video : shown(t === "ring" ? "visualizer" : "lyrics")));
    }

    function fire(strength) {
        const list = candidates();
        if (!list.length)
            return;
        // The same target twice in a row only if there's no other
        const fresh = list.filter(t => t !== last);
        const pool = fresh.length ? fresh : list;
        target = strength > 0.95 && Math.random() < 0.3 && list.length > 1 ? "all" : pool[Math.floor(Math.random() * pool.length)];
        if (target !== "all")
            last = target;
        burstId = (burstId + 1) % 1000;
        seed = burstId + Math.random();
        // The wallpaper is big enough that a short burst reads as a couple of frames
        duration = (0.15 + Math.random() * 0.15) * (target === "wall" ? 1.3 : 1);
        level = 0.5 + strength * 0.5;
        life = 1;
        burst = level;
        beats = 0;
        // A hard hit stutters: the same burst comes back a beat-fraction later
        echo = strength > 0.9 && Math.random() < 0.5 ? duration + 0.04 + Math.random() * 0.06 : -1;
        since = 0;
        reseed = 0;
    }

    Connections {
        target: Cava
        enabled: root.on

        // Relative to the recent loudest kick, so quiet tracks glitch too
        function onKickChanged() {
            const k = Cava.kick;
            root.peak = Math.max(root.peak * 0.995, k, 0.05);
            // Not every beat: a steady four-on-the-floor would glitch nonstop, so it lands on every
            // other kick, plus any hard one
            if (k - root.lastKick > 0.03 && k > root.peak * 0.7 && root.since > 0.25) {
                root.beats++;
                if (k > root.peak * 0.95 || root.beats >= 2)
                    root.fire(k / root.peak);
            }
            root.lastKick = k;
        }
    }

    onOnChanged: {
        if (!on) {
            burst = 0;
            target = "";
        }
    }

    FrameAnimation {
        running: root.on
        onTriggered: {
            root.since += frameTime;
            if (root.echo > 0 && root.since >= root.echo && root.burst === 0 && root.target === "") {
                root.echo = -1;
                root.target = root.last;
                root.level *= 0.8;
                root.life = 1;
                root.burst = root.level;
                root.since = 0;
            }
            if (root.burst <= 0)
                return;
            // Holds, then drops in hard steps: digital, not a fade
            root.life = Math.max(0, root.life - frameTime / root.duration);
            root.burst = root.level * Math.ceil(root.life * 3) / 3;
            // New strips every few frames, so a burst flickers instead of freezing
            root.reseed += frameTime;
            if (root.reseed > (root.target === "wall" ? 0.03 : 0.05)) {
                root.reseed = 0;
                root.seed = root.burstId + Math.random();
            }
            if (root.burst === 0)
                root.target = "";
        }
    }
}
