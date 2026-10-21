pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// sing-box through its clash API: on/off via systemd, server choice via the "proxy" selector
Singleton {
    id: root

    readonly property string api: "http://127.0.0.1:9090"
    readonly property string unit: "sing-box"
    readonly property string testUrl: "https://www.gstatic.com/generate_204"

    property bool on: false
    // Toggled but systemd hasn't caught up yet
    property bool busy: false
    property string selected: ""
    // What "auto" currently resolves to
    property string autoPick: ""
    property var servers: []
    property var delays: ({})
    readonly property bool testing: tester.running
    readonly property bool updating: updater.running
    // flag-icons (MIT) SVGs, fetched once per country into the cache
    readonly property string flagDir: Quickshell.cachePath("flags")
    property int flagsGen: 0
    readonly property string current: selected === "auto" ? autoPick : selected

    // "🇳🇱Нидерланды CDN" -> { flag: "🇳🇱", code: "NL", name: "Нидерланды CDN" }
    function split(tag) {
        // Each regional indicator is a surrogate pair, so the flag is 4 UTF-16 units
        const ri = i => (tag.codePointAt(i) ?? 0) - 0x1F1E6;
        const a = ri(0), b = ri(2);
        if (a >= 0 && a < 26 && b >= 0 && b < 26)
            return { flag: tag.slice(0, 4), code: String.fromCharCode(65 + a, 65 + b), name: tag.slice(4).trim() };
        return { flag: "", code: "", name: tag };
    }

    function toggle() {
        busy = true;
        busyTimer.restart();
        Quickshell.execDetached(["systemctl", on ? "stop" : "start", unit]);
    }

    function use(tag) {
        selected = tag;
        Quickshell.execDetached(["curl", "-s", "--noproxy", "*", "-m", "3", "-X", "PUT",
            "-H", "Content-Type: application/json", "-d", JSON.stringify({ name: tag }), api + "/proxies/proxy"]);
        refreshSoon.restart();
    }

    function test() {
        if (on && !tester.running)
            tester.running = true;
    }

    // Oneshot unit: systemctl returns once the refresh is done
    function update() {
        if (!updater.running)
            updater.running = true;
    }

    Process {
        id: updater
        command: ["systemctl", "start", "vpn-update.service"]
        onExited: {
            refreshSoon.restart();
            root.test();
        }
    }

    function flag(code) {
        return code && flagsGen > 0 ? `file://${flagDir}/${code.toLowerCase()}.svg` : "";
    }

    onServersChanged: {
        const codes = [...new Set(servers.map(t => split(t).code.toLowerCase()).filter(c => c))];
        if (!codes.length)
            return;
        flagFetch.command = ["sh", "-c", `mkdir -p "$0" && for c in "$@"; do [ -s "$0/$c.svg" ] || curl -sf -m 10 -o "$0/$c.svg" "https://cdn.jsdelivr.net/gh/lipis/flag-icons@7/flags/4x3/$c.svg"; done; true`, flagDir, ...codes];
        flagFetch.running = true;
    }

    Process {
        id: flagFetch
        onExited: root.flagsGen++
    }

    Timer {
        id: busyTimer
        interval: 15000
        onTriggered: root.busy = false
    }

    Timer {
        id: refreshSoon
        interval: 400
        onTriggered: poller.running = true
    }

    Timer {
        interval: root.busy ? 1000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!poller.running) poller.running = true
    }

    Process {
        id: poller
        command: ["sh", "-c", `systemctl is-active --quiet ${root.unit} && echo on || echo off; curl -s --noproxy '*' -m 2 ${root.api}/proxies`]
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n");
                const active = text.slice(0, nl) === "on";
                let proxies = null;
                try {
                    proxies = JSON.parse(text.slice(nl + 1)).proxies;
                } catch (e) {}
                const ready = active && proxies?.proxy;
                if (root.busy && (ready || (!active && root.on)))
                    root.busy = false;
                root.on = active;
                if (!ready)
                    return;
                root.selected = proxies.proxy.now;
                root.autoPick = proxies.auto?.now ?? "";
                const all = proxies.proxy.all;
                if (JSON.stringify(all) !== JSON.stringify(root.servers))
                    root.servers = all;
                // urltest history fills in between explicit tests
                const d = Object.assign({}, root.delays);
                for (const tag of all) {
                    const h = proxies[tag]?.history ?? [];
                    if (h.length && !(tag in d))
                        d[tag] = h[h.length - 1].delay;
                }
                root.delays = d;
            }
        }
    }

    Process {
        id: tester
        command: ["curl", "-s", "--noproxy", "*", "-m", "6",
            `${root.api}/group/proxy/delay?timeout=4000&url=${encodeURIComponent(root.testUrl)}`]
        stdout: StdioCollector {
            onStreamFinished: {
                let res = {};
                try {
                    res = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const d = {};
                // Missing from the reply = timed out
                for (const tag of root.servers)
                    d[tag] = res[tag] ?? 0;
                root.delays = d;
            }
        }
    }
}
