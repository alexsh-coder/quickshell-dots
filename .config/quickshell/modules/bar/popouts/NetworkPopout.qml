import QtQuick
import Quickshell.Networking
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property var wifi: Net.wifi
    readonly property int rowHeight: 40
    readonly property int maxRows: 5
    // Adapter whose networks are listed; changes when the picker is used
    property var shownWifi: null
    // Guards the adapter switch handler until the panel is built
    property bool ready: false

    // Rows are synced in place, so opening the panel never rebuilds the list
    property var byName: ({})
    // Network whose password field is open
    property var asking: null
    // Stand-in for a row whose network vanished before the list caught up
    readonly property var ghost: ({ name: "", connected: false, known: false, signalStrength: 0, security: -1, stateChanging: false, state: 0 })

    implicitWidth: 330
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    ListModel {
        id: rows
    }

    // One entry per name: the connected one, otherwise the strongest
    function refresh() {
        if (asking)
            return;
        const best = {};
        for (const n of wifi?.networks.values ?? []) {
            if (!n.name)
                continue;
            const b = best[n.name];
            if (!b || n.connected || (!b.connected && n.signalStrength > b.signalStrength))
                best[n.name] = n;
        }
        const names = Object.keys(best).sort((x, y) => {
            const a = best[x], b = best[y];
            return (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength);
        }).slice(0, 24);
        // Rows being removed still resolve until they're gone
        byName = Object.assign({}, byName, best);

        for (let i = 0; i < names.length; i++) {
            if (i < rows.count && rows.get(i).name === names[i])
                continue;
            let j = i + 1;
            while (j < rows.count && rows.get(j).name !== names[i])
                j++;
            if (j < rows.count)
                rows.move(j, i, 1);
            else
                rows.insert(i, { name: names[i] });
        }
        if (rows.count > names.length)
            rows.remove(names.length, rows.count - names.length);
        byName = best;
    }

    function ask(net) {
        asking = net;
        popouts.pinned = true;
    }

    function stopAsking() {
        asking = null;
        popouts.pinned = false;
        refresh();
    }

    // Another adapter became the one shown: drop the old rows and scan the new card
    function switchAdapter() {
        if (!ready)
            return;
        if (asking)
            stopAsking();
        // Stop scanning the adapter we're leaving; it may already be gone
        if (shownWifi && shownWifi !== wifi && Net.wifiDevices.indexOf(shownWifi) !== -1)
            shownWifi.scannerEnabled = false;
        shownWifi = wifi;
        rows.clear();
        byName = {};
        refresh();
        if (here && wifi)
            wifi.scannerEnabled = true;
    }

    function activate(net) {
        if (net.connected || net.stateChanging)
            return;
        if (net.known || !Net.secured(net) || Net.enterprise(net))
            net.connect();
        else
            ask(net);
    }

    onHereChanged: if (!here && asking) stopAsking()
    onWifiChanged: switchAdapter()
    Component.onCompleted: {
        ready = true;
        shownWifi = wifi;
        refresh();
    }

    // Scan only once the panel has settled, so the first results don't jolt the opening
    // Unknown networks drop out of the list while the scanner is off, so it keeps
    // running for a while after the panel closes
    property bool scanning: false
    onScanningChanged: if (wifi) wifi.scannerEnabled = scanning

    Timer {
        interval: Theme.animSpatial
        running: root.here
        onTriggered: root.scanning = true
    }

    Timer {
        id: scanIdle
        interval: 120000
        onTriggered: root.scanning = false
    }

    Connections {
        target: root
        function onHereChanged() {
            if (root.here)
                scanIdle.stop();
            else
                scanIdle.restart();
        }
    }

    Connections {
        target: root.wifi?.networks ?? null
        function onValuesChanged() { root.refresh(); }
    }

    Connections {
        target: root.popouts
        function onPinnedChanged() {
            if (!root.popouts.pinned && root.asking)
                root.stopAsking();
        }
    }

    Column {
        id: content

        x: Theme.pad
        y: Theme.padTop
        width: parent.width - Theme.pad * 2
        spacing: 10

        Item {
            width: parent.width
            height: 28

            Icon {
                id: wifiIcon
                anchors.verticalCenter: parent.verticalCenter
                text: Net.wifiOn ? "wifi" : "wifi_off"
                font.pixelSize: 20
                color: Net.wifiOn ? Theme.accent : Theme.subtext
            }

            Label {
                anchors.left: wifiIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Wi-Fi"
                font.pixelSize: 14
            }

            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: Net.wifiOn
                onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }

        // Adapter picker, only when the machine has more than one Wi-Fi card
        Row {
            id: adapters

            visible: Net.wifiDevices.length > 1
            width: parent.width
            height: 28
            spacing: 6

            Repeater {
                model: Net.wifiDevices

                delegate: Rectangle {
                    id: chip

                    required property var modelData
                    readonly property bool selected: modelData === root.wifi

                    width: chipContent.implicitWidth + 20
                    height: 28
                    radius: Theme.radius - 4
                    color: selected ? Qt.alpha(Theme.accent, 0.14) : chipMouse.containsMouse ? Theme.surface : Qt.alpha(Theme.surface, 0)
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Row {
                        id: chipContent

                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "wifi"
                            font.pixelSize: 14
                            color: chip.selected ? Theme.accent : Theme.subtext
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.name
                            font.pixelSize: 12
                            color: chip.selected ? Theme.text : Theme.subtext
                        }

                        // Adapter that currently carries the connection
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chip.modelData.connected
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                        onReleased: if (containsMouse) Sfx.tap("clickPop")

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Net.wifiName = chip.modelData.name
                    }
                }
            }
        }

        // Wired link, only when a cable is plugged in
        Rectangle {
            visible: Net.wired?.hasLink ?? false
            width: parent.width
            height: root.rowHeight
            radius: Theme.radius - 2
            color: Theme.surface

            NerdIcon {
                id: ethIcon
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0200}"
                font.pixelSize: 18
                color: Net.ethernet ? Theme.accent : Theme.subtext
            }

            Label {
                anchors.left: ethIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Ethernet"
                font.pixelSize: 13
            }

            Label {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: Net.ethernet ? (Net.wired.linkSpeed ? Net.wired.linkSpeed + " Mb/s" : "Connected") : "Not connected"
                font.pixelSize: 12
                color: Theme.subtext
            }
        }

        Label {
            visible: !Net.wifiOn || rows.count === 0
            width: parent.width
            height: Net.wifiOn ? list.height : 36
            horizontalAlignment: Text.AlignHCenter
            text: !Net.wifiOn ? "Wi-Fi is off" : "Searching…"
            font.pixelSize: 13
            color: Theme.subtext
        }

        ListView {
            id: list

            // Fixed height, so late scan results fill in instead of resizing the panel
            visible: Net.wifiOn && rows.count > 0
            width: parent.width
            height: root.maxRows * (root.rowHeight + spacing) - spacing + (root.asking ? 46 : 0)
            spacing: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: rows
            delegate: NetRow {}

            move: Transition { NumberAnimation { property: "y"; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            moveDisplaced: Transition { NumberAnimation { property: "y"; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            displaced: Transition { NumberAnimation { property: "y"; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim } }

            ListSettle { view: list }
        }
    }

    component NetRow: Item {
        id: row

        required property string name
        required property int index
        readonly property var net: root.byName[name] ?? root.ghost
        readonly property bool asked: root.asking === net
        readonly property bool busy: net.stateChanging || net.state === ConnectionState.Connecting
        property string error: ""

        width: ListView.view.width
        height: root.rowHeight + (asked ? 46 : 0)
        visible: net !== root.ghost
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }

        Connections {
            target: row.net === root.ghost ? null : row.net
            function onConnectionFailed(reason) {
                if (reason === ConnectionFailReason.NoSecrets && !row.asked && Net.secured(row.net) && !Net.enterprise(row.net)) {
                    root.ask(row.net);
                    return;
                }
                row.error = row.asked ? "Wrong password" : "Failed";
                if (row.asked) {
                    field.text = "";
                    shake.restart();
                }
                errorTimer.restart();
            }
            function onConnectedChanged() {
                if (row.net.connected && row.asked)
                    root.stopAsking();
            }
        }

        Timer {
            id: errorTimer
            interval: 3000
            onTriggered: row.error = ""
        }

        Rectangle {
            width: parent.width
            height: root.rowHeight
            radius: Theme.radius - 2
            color: row.net.connected ? Qt.alpha(Theme.accent, 0.12) : rowHover.hovered || row.asked ? Theme.surface : Qt.alpha(Theme.surface, 0)
            Behavior on color { ColorAnimation { duration: Theme.anim } }

            NerdIcon {
                id: strength
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: Net.glyph(row.net.signalStrength)
                font.pixelSize: 18
                color: row.net.connected ? Theme.accent : Theme.subtext
                SequentialAnimation on opacity {
                    running: row.busy
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) strength.opacity = 1
                    NumberAnimation { to: 0.3; duration: 450; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
                }
            }

            Label {
                anchors.left: strength.right
                anchors.leftMargin: 10
                anchors.right: tail.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.net.name
                elide: Text.ElideRight
                font.pixelSize: 13
                color: row.net.connected ? Theme.text : row.net.known ? Theme.text : Theme.subtext
            }

            Row {
                id: tail

                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: row.error || (row.busy ? "Connecting…" : "")
                    font.pixelSize: 12
                    color: row.error ? Theme.urgent : Theme.subtext
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Net.secured(row.net) && !row.net.connected
                    text: "lock"
                    font.pixelSize: 15
                    fill: 0
                    color: Theme.subtext
                }

                // Disconnect, shown on the connected row
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.net.connected
                    width: 26
                    height: 26
                    radius: 13
                    color: unlink.containsMouse ? Qt.alpha(Theme.urgent, 0.18) : Qt.alpha(Theme.urgent, 0)
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Icon {
                        anchors.centerIn: parent
                        text: unlink.containsMouse ? "link_off" : "check"
                        font.pixelSize: 17
                        color: unlink.containsMouse ? Theme.urgent : Theme.accent
                    }

                    MouseArea {
                        id: unlink
                        onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                        onReleased: if (containsMouse) Sfx.tap("clickPop")
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.net.disconnect()
                    }
                }
            }

            // Unlike MouseArea hover, child buttons don't steal it
            HoverHandler {
                id: rowHover
            }

            MouseArea {
                id: mouse
                onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
                onReleased: if (containsMouse) Sfx.tap("clickPop")
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: row.net.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: row.asked ? root.stopAsking() : root.activate(row.net)
            }
        }

        // Password field
        Rectangle {
            id: box

            x: 0
            y: root.rowHeight + 6
            width: parent.width
            height: 36
            radius: Theme.radius - 2
            color: Theme.surface
            border.width: 1
            border.color: row.error ? Theme.urgent : field.activeFocus ? Theme.accent : Theme.muted
            opacity: row.asked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
            Behavior on border.color { ColorAnimation { duration: Theme.anim } }

            transform: Translate { id: shakeShift }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeShift; property: "x"; to: -8; duration: 50 }
                NumberAnimation { target: shakeShift; property: "x"; to: 7; duration: 70 }
                NumberAnimation { target: shakeShift; property: "x"; to: -4; duration: 70 }
                NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 90; easing.type: Easing.OutCubic }
            }

            TextInput {
                id: field

                anchors.left: parent.left
                anchors.right: go.left
                anchors.margins: 12
                anchors.verticalCenter: parent.verticalCenter
                echoMode: shown.checked ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.text
                selectionColor: Qt.alpha(Theme.accent, 0.4)
                clip: true
                enabled: row.asked

                onEnabledChanged: {
                    text = "";
                    if (enabled)
                        forceActiveFocus();
                }
                onAccepted: if (text.length >= 8) row.net.connectWithPsk(text)
                Keys.onEscapePressed: root.stopAsking()

                Label {
                    visible: !field.text
                    text: "Password"
                    font.pixelSize: 13
                    color: Theme.subtext
                }
            }

            Row {
                id: go

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                IconButton {
                    id: shown
                    property bool checked: false
                    icon: checked ? "visibility_off" : "visibility"
                    onClicked: checked = !checked
                }

                IconButton {
                    icon: row.busy ? "progress_activity" : "arrow_forward"
                    accent: field.text.length >= 8
                    onClicked: field.accepted()
                }
            }
        }
    }

    component IconButton: Rectangle {
        id: btn

        property string icon
        property bool accent: false
        signal clicked

        width: 26
        height: 26
        radius: 13
        color: btnMouse.containsMouse ? Theme.muted : Qt.alpha(Theme.muted, 0)
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Icon {
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: 17
            color: btn.accent ? Theme.accent : Theme.subtext
        }

        MouseArea {
            id: btnMouse
            onContainsMouseChanged: if (containsMouse) Sfx.play("hoverPop")
            onReleased: if (containsMouse) Sfx.tap("clickPop")
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
