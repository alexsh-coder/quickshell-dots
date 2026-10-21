pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property list<string> ids: adapter.ids

    function save(ids) {
        adapter.ids = ids;
    }

    FileView {
        path: Quickshell.statePath("pins.json")
        // Load synchronously so the first open after a restart already sees the data
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
            property list<string> ids: []
        }
    }
}
