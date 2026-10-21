pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// App names set from the launcher, by desktop entry id; the entries themselves are left untouched
Singleton {
    id: root

    readonly property var names: adapter.names

    function name(entry) {
        return entry ? adapter.names[entry.id] ?? entry.name : "";
    }

    // An empty name drops the override
    function rename(id, name) {
        const names = Object.assign({}, adapter.names);
        if (name)
            names[id] = name;
        else
            delete names[id];
        adapter.names = names;
    }

    FileView {
        path: Quickshell.statePath("names.json")
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
            property var names: ({})
        }
    }
}
