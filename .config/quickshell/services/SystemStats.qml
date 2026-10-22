pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU, RAM and GPU load, polled only while something shows them
Singleton {
    id: root

    property bool active: false
    // Desktop widgets showing the stats, counted so several can come and go
    property int users: 0
    property real cpu: 0
    property real ram: 0
    property real gpu: -1
    property real ramUsedGb: 0

    property var lastCpu: null

    Timer {
        interval: 1500
        running: root.active || root.users > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            mem.reload();
            if (gpuFile.path)
                gpuFile.reload();
        }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] ?? 0);
            const total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu && total > root.lastCpu.total)
                root.cpu = 1 - (idle - root.lastCpu.idle) / (total - root.lastCpu.total);
            root.lastCpu = { idle, total };
        }
    }

    FileView {
        id: mem
        path: "/proc/meminfo"
        onLoaded: {
            const get = key => Number(text().match(new RegExp("^" + key + ":\\s+(\\d+)", "m"))?.[1] ?? 0);
            const total = get("MemTotal"), avail = get("MemAvailable");
            if (total) {
                root.ram = 1 - avail / total;
                root.ramUsedGb = (total - avail) / 1048576;
            }
        }
    }

    // amdgpu and i915 (recent) expose a busy percentage; stays -1 elsewhere
    FileView {
        id: gpuFile
        printErrors: false
        onLoaded: root.gpu = Number(text().trim()) / 100
    }

    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: gpuFile.path = text.trim()
        }
    }
}
