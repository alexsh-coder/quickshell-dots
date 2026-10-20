pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Audio spectrum from cava, only sampled while some player is playing
Singleton {
    id: root

    readonly property int bars: 48
    readonly property bool active: Mpris.players.values.some(p => p.isPlaying)
    // Spectrum scaled by MusicFx.intensity, clamped to 0..1
    property list<real> values: Array(bars).fill(0)
    // Overall loudness and a punchy low-end envelope: fast attack, slow release
    property real level: 0
    property real bass: 0
    // Screen-shake "trauma": jumps on kicks, then drains
    property real kick: 0

    property real bassAvg: 0

    onActiveChanged: if (!active) reset()

    function reset() {
        values = Array(bars).fill(0);
        level = 0;
        bass = 0;
        kick = 0;
        bassAvg = 0;
    }

    // Averages the spectrum down to n bars, for small widgets
    function downsample(n) {
        const step = bars / n;
        const out = [];
        for (let i = 0; i < n; i++) {
            let s = 0;
            for (let j = Math.floor(i * step); j < Math.floor((i + 1) * step); j++)
                s += values[j];
            out.push(s / Math.max(1, Math.floor((i + 1) * step) - Math.floor(i * step)));
        }
        return out;
    }

    function feed(raw) {
        const gain = MusicFx.intensity;
        const v = raw.map(n => Math.min(1, n / 100 * gain));
        values = v;

        let sum = 0, low = 0;
        const lowN = Math.round(bars / 8);
        for (let i = 0; i < bars; i++) {
            sum += v[i];
            if (i < lowN)
                low += v[i];
        }
        level = level * 0.7 + sum / bars * 0.3;
        low /= lowN;
        bass = low > bass ? bass + (low - bass) * 0.6 : bass * 0.9 + low * 0.1;

        // A kick is low end jumping well above its recent average
        const hit = Math.max(0, low - bassAvg - 0.12) * 2.5;
        bassAvg = bassAvg * 0.95 + low * 0.05;
        kick = Math.min(1, Math.max(kick - 0.035, hit));
    }

    Process {
        running: root.active
        command: ["sh", "-c", `exec cava -p /dev/stdin <<EOF
[general]
bars = ${root.bars}
framerate = 60
[input]
method = pipewire
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
bar_delimiter = 59
frame_delimiter = 10
channels = mono
[smoothing]
noise_reduction = 70
EOF`]
        stdout: SplitParser {
            onRead: data => {
                const v = data.split(";", root.bars).map(Number);
                if (v.length === root.bars)
                    root.feed(v);
            }
        }
    }
}
