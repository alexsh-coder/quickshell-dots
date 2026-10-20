pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Launch history with exponential decay: recent launches outweigh old ones
Singleton {
    id: root

    readonly property real halfLife: 7 * 24 * 3600 * 1000

    function rank(entry, now) {
        return entry ? entry.score * Math.pow(0.5, (now - entry.last) / halfLife) : 0;
    }

    function ranks() {
        const now = Date.now();
        const out = {};
        for (const id in adapter.apps)
            out[id] = rank(adapter.apps[id], now);
        return out;
    }

    function record(id) {
        const now = Date.now();
        const apps = Object.assign({}, adapter.apps);
        apps[id] = { score: rank(apps[id], now) + 1, last: now };
        adapter.apps = apps;
    }

    FileView {
        path: Quickshell.statePath("usage.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property var apps: ({})
        }
    }
}
