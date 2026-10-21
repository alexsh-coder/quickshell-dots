pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Cover art downloaded once into the disk cache as soon as a track starts, so every view
// opens a local file instead of each doing its own slow TLS fetch
Singleton {
    id: root

    readonly property string dir: Quickshell.cachePath("art")
    // Remote url -> local file url, once downloaded
    property var files: ({})
    property var pending: ({})

    // What an Image should load: the cached copy, the url itself if it's already local, or nothing yet
    function local(url) {
        if (!/^https?:/.test(url))
            return url;
        return files[url] ?? "";
    }

    function fetch(url) {
        if (!/^https?:/.test(url) || url in files || url in pending)
            return;
        pending[url] = true;
        job.createObject(root, { url: url, path: dir + "/" + Qt.md5(url) });
    }

    Instantiator {
        model: Mpris.players

        delegate: QtObject {
            required property MprisPlayer modelData
            readonly property string art: modelData.trackArtUrl

            onArtChanged: root.fetch(art)
            Component.onCompleted: root.fetch(art)
        }
    }

    Component {
        id: job

        Process {
            id: proc

            required property string url
            required property string path

            // A hit only refreshes the mtime, which keeps it from being pruned
            command: ["sh", "-c", `
                mkdir -p "$(dirname "$2")"
                if [ -s "$2" ]; then touch "$2"; exit; fi
                curl -sfL -m 20 --retry 2 -o "$2.part" "$1" && mv "$2.part" "$2" || { rm -f "$2.part"; exit 1; }
                find "$(dirname "$2")" -type f -mtime +30 -delete`, "sh", url, path]
            running: true

            onExited: code => {
                delete root.pending[url];
                if (code === 0)
                    root.files = Object.assign({}, root.files, { [url]: "file://" + path });
                proc.destroy();
            }
        }
    }
}
