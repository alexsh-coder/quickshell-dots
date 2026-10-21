pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    // Newest first. Entries copy what they show, so a card can still animate
    // out after the sender has closed its notification
    property var list: []
    readonly property var popups: list.filter(n => n.popup)
    property bool dnd: false
    readonly property int maxHistory: 50

    function add(n) {
        // Carried over by keepOnReload: back into history without popping
        const pop = !n.lastGeneration && (!dnd || n.urgency === NotificationUrgency.Critical);
        const entry = entryComp.createObject(root, { notification: n, popup: pop });
        list = [entry, ...list];
        for (const old of list.slice(maxHistory))
            old.close();
    }

    function clear() {
        for (const n of list.slice())
            n.close();
    }

    function hidePopups() {
        for (const n of popups)
            n.popup = false;
    }

    function setDnd(on) {
        dnd = on;
        if (on)
            hidePopups();
        saved.setText(on ? "1" : "0");
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            root.add(n);
        }
    }

    component Entry: QtObject {
        id: entry

        property Notification notification
        property bool popup: false
        onNotificationChanged: if (!notification) forget()
        readonly property date time: new Date()

        property string appName: ""
        property string appIcon: ""
        property string desktopEntry: ""
        property string image: ""
        property string summary: ""
        property string body: ""
        property int urgency: NotificationUrgency.Normal
        property int timeout: -1
        property var actions: []

        // An updated notification (same id) pops up again with a fresh timer
        signal refreshed

        function copy() {
            const n = notification;
            appName = n.appName;
            appIcon = n.appIcon;
            desktopEntry = n.desktopEntry;
            image = n.image;
            summary = n.summary;
            body = n.body;
            urgency = n.urgency;
            timeout = n.expireTimeout;
            actions = n.actions.map(a => ({ id: a.identifier, text: a.text }));
        }

        function invoke(id) {
            notification?.actions.find(a => a.identifier === id)?.invoke();
        }

        function close() {
            if (notification)
                notification.dismiss();
            else
                forget();
        }

        function forget() {
            popup = false;
            root.list = root.list.filter(n => n !== entry);
            // Outlives the card's exit animation
            reaper.start();
        }

        readonly property Timer reaper: Timer {
            interval: 1000
            onTriggered: entry.destroy()
        }

        readonly property Connections watch: Connections {
            target: entry.notification

            function onClosed() { entry.forget(); }
            function onSummaryChanged() { entry.update(); }
            function onBodyChanged() { entry.update(); }
            function onImageChanged() { entry.update(); }
        }

        function update() {
            copy();
            if (!root.dnd || urgency === NotificationUrgency.Critical)
                popup = true;
            refreshed();
        }

        Component.onCompleted: copy()
    }

    Component {
        id: entryComp
        Entry {}
    }

    FileView {
        id: saved
        path: Quickshell.statePath("dnd")
        blockLoading: true
        printErrors: false
    }

    IpcHandler {
        target: "notifs"

        function dnd(action: string): void {
            root.setDnd(action === "toggle" ? !root.dnd : action === "on");
        }

        function clear(): void {
            root.clear();
        }

        function hide(): void {
            root.hidePopups();
        }
    }

    Component.onCompleted: {
        dnd = saved.text().trim() === "1";
    }
}
