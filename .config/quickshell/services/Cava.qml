pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Audio spectrum from cava, only sampled while some player is playing
Singleton {
    id: root

    readonly property int bars: 12
    readonly property bool active: Mpris.players.values.some(p => p.isPlaying)
    property list<real> values: Array(bars).fill(0)

    onActiveChanged: if (!active) values = Array(bars).fill(0)

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
                const v = data.split(";", root.bars).map(n => n / 100);
                if (v.length === root.bars)
                    root.values = v;
            }
        }
    }
}
