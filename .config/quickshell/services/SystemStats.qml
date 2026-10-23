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
    // Degrees Celsius, -1 when no sensor was found
    property real cpuTemp: -1
    property real gpuTemp: -1
    property bool nvidia: false

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
            if (cpuTempFile.path)
                cpuTempFile.reload();
            if (gpuTempFile.path)
                gpuTempFile.reload();
            if (root.nvidia && !smi.running)
                smi.running = true;
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

    FileView {
        id: cpuTempFile
        printErrors: false
        onLoaded: root.cpuTemp = Number(text().trim()) / 1000
    }

    FileView {
        id: gpuTempFile
        printErrors: false
        onLoaded: root.gpuTemp = Number(text().trim()) / 1000
    }

    // NVIDIA has no sysfs load or temperature, ask the driver instead
    Process {
        id: smi
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [load, temp] = text.split("\n")[0].split(",").map(Number);
                if (!isNaN(load))
                    root.gpu = load / 100;
                if (!isNaN(temp))
                    root.gpuTemp = temp;
            }
        }
    }

    // Prints key=value lines for the sensors this machine has
    Process {
        running: true
        command: ["sh", "-c", `
            echo busy=$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1)
            for h in /sys/class/hwmon/hwmon*; do
                case $(cat $h/name) in
                    coretemp|k10temp|zenpower) echo cpu=$h/temp1_input;;
                    amdgpu|radeon) echo gpu=$h/temp1_input;;
                esac
            done
            [ -e /dev/nvidiactl ] && command -v nvidia-smi >/dev/null && echo nvidia=1`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i > 0 && !(l.slice(0, i) in kv))
                        kv[l.slice(0, i)] = l.slice(i + 1);
                }
                gpuFile.path = kv.busy ?? "";
                cpuTempFile.path = kv.cpu ?? "";
                gpuTempFile.path = kv.gpu ?? "";
                root.nvidia = kv.nvidia === "1";
            }
        }
    }
}
