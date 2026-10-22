pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Desktop entry ids shown in the dock, in order
Singleton {
    id: root

    readonly property list<string> ids: adapter.ids

    function has(id) {
        return ids.includes(id);
    }

    function save(ids) {
        adapter.ids = ids;
    }

    function toggle(id) {
        const next = ids.slice();
        const i = next.indexOf(id);
        if (i >= 0)
            next.splice(i, 1);
        else
            next.push(id);
        adapter.ids = next;
    }

    FileView {
        path: Quickshell.statePath("dock.json")
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property list<string> ids: ["kitty", "org.telegram.desktop", "zen", "spotify-launcher"]
        }
    }
}
