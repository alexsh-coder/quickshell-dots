import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.config
import qs.components

Item {
    id: root

    required property Item popouts
    property bool here: false

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property int rowHeight: 40
    readonly property int maxRows: 5

    // Nameless devices only have an address, which says nothing to a person
    function named(d) {
        return d.name && d.name.replace(/-/g, ":") !== d.address;
    }

    readonly property var devices: on ? Bluetooth.devices.values.filter(named).sort((a, b) =>
        (b.connected - a.connected) || (b.bonded - a.bonded) || a.name.localeCompare(b.name)) : []

    function icon(d) {
        const name = d.icon ?? "";
        const rules = [[["headset", "headphones"], "headphones"], [["audio"], "speaker"],
                       [["phone"], "smartphone"], [["mouse"], "mouse"], [["keyboard"], "keyboard"],
                       [["gaming"], "sports_esports"], [["computer"], "computer"]];
        for (const [needles, result] of rules)
            if (needles.some(n => name.includes(n)))
                return result;
        return "bluetooth";
    }

    function activate(d) {
        if (d.connected || d.pairing || d.state !== BluetoothDeviceState.Disconnected)
            return;
        if (d.bonded) {
            d.connect();
        } else {
            // Without it the kernel pairs without bonding and nothing is remembered
            if (!adapter.pairable)
                adapter.pairable = true;
            pending.push(d);
            d.pair();
        }
    }

    // Freshly paired devices get trusted and connected right away
    property var pending: []

    Connections {
        target: Bluetooth.devices
        function onValuesChanged() {
            root.pending = root.pending.filter(d => Bluetooth.devices.values.includes(d));
        }
    }

    implicitWidth: 330
    implicitHeight: content.implicitHeight + Theme.padTop + Theme.pad

    // Discover once the panel has settled, and a bit longer after it closes
    property bool scanning: false
    onScanningChanged: if (adapter && on) adapter.discovering = scanning

    Timer {
        interval: Theme.animSpatial
        running: root.here && root.on
        onTriggered: root.scanning = true
    }

    Timer {
        id: scanIdle
        interval: 30000
        onTriggered: root.scanning = false
    }

    onHereChanged: here ? scanIdle.stop() : scanIdle.restart()
    onOnChanged: if (!on) scanning = false

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
                id: btIcon
                anchors.verticalCenter: parent.verticalCenter
                text: root.on ? "bluetooth" : "bluetooth_disabled"
                font.pixelSize: 20
                color: root.on ? Theme.accent : Theme.subtext
                SequentialAnimation on opacity {
                    running: root.adapter?.discovering ?? false
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) btIcon.opacity = 1
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            Label {
                anchors.left: btIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Bluetooth"
                font.pixelSize: 14
            }

            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.on
                onToggled: if (root.adapter) root.adapter.enabled = !root.on
            }
        }

        Label {
            visible: root.devices.length === 0
            width: parent.width
            height: root.on ? list.height : 36
            horizontalAlignment: Text.AlignHCenter
            text: !root.adapter ? "No adapter" : !root.on ? "Bluetooth is off" : "Searching…"
            font.pixelSize: 13
            color: Theme.subtext
        }

        ListView {
            id: list

            // Fixed height, so devices found later fill in instead of resizing the panel
            visible: root.devices.length > 0
            width: parent.width
            height: root.maxRows * (root.rowHeight + spacing) - spacing
            spacing: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: root.devices }
            delegate: DeviceRow {}

            move: Transition { NumberAnimation { property: "y"; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            moveDisplaced: Transition { NumberAnimation { property: "y"; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            displaced: Transition { NumberAnimation { property: "y"; duration: Theme.animSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spatial } }
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim } }
        }
    }

    component DeviceRow: Rectangle {
        id: row

        required property BluetoothDevice modelData
        readonly property BluetoothDevice dev: modelData
        readonly property bool busy: dev.pairing || dev.state === BluetoothDeviceState.Connecting
                                  || dev.state === BluetoothDeviceState.Disconnecting

        width: ListView.view.width
        height: root.rowHeight
        radius: Theme.radius - 2
        color: dev.connected ? Qt.alpha(Theme.accent, 0.12) : mouse.containsMouse ? Theme.surface : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Connections {
            target: row.dev
            function onPairedChanged() {
                if (!row.dev.paired || !root.pending.includes(row.dev))
                    return;
                root.pending = root.pending.filter(d => d !== row.dev);
                row.dev.trusted = true;
                row.dev.connect();
            }
        }

        Icon {
            id: kind
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon(row.dev)
            font.pixelSize: 18
            color: row.dev.connected ? Theme.accent : Theme.subtext
            SequentialAnimation on opacity {
                running: row.busy
                loops: Animation.Infinite
                onRunningChanged: if (!running) kind.opacity = 1
                NumberAnimation { to: 0.3; duration: 450; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
            }
        }

        Label {
            anchors.left: kind.right
            anchors.leftMargin: 10
            anchors.right: tail.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.dev.name
            elide: Text.ElideRight
            font.pixelSize: 13
            color: row.dev.connected || row.dev.bonded ? Theme.text : Theme.subtext
        }

        Row {
            id: tail

            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: row.dev.pairing ? "Pairing…"
                    : row.dev.state === BluetoothDeviceState.Connecting ? "Connecting…"
                    : row.dev.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                    : row.dev.connected && row.dev.batteryAvailable ? Math.round(row.dev.battery * 100) + "%"
                    : ""
                font.pixelSize: 12
                color: row.dev.connected && row.dev.batteryAvailable && row.dev.battery < 0.2 ? Theme.urgent : Theme.subtext
            }

            // Forget, for paired devices that aren't connected
            RoundButton {
                visible: row.dev.bonded && !row.dev.connected && !row.busy && mouse.containsMouse
                icon: "delete"
                danger: true
                onClicked: row.dev.forget()
            }

            // Disconnect, shown on the connected row
            RoundButton {
                visible: row.dev.connected && !row.busy
                icon: hovered ? "link_off" : "check"
                tint: Theme.accent
                danger: true
                onClicked: row.dev.disconnect()
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: row.dev.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: root.activate(row.dev)
        }
    }

    component RoundButton: Rectangle {
        id: btn

        property string icon
        property color tint: Theme.subtext
        property bool danger: false
        readonly property bool hovered: btnMouse.containsMouse
        signal clicked

        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 13
        color: hovered ? Qt.alpha(danger ? Theme.urgent : Theme.text, 0.18) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.anim } }

        Icon {
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: 17
            color: btn.hovered && btn.danger ? Theme.urgent : btn.tint
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
