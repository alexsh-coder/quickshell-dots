import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts

// Quick settings card in the middle of the focused screen. Full pages
// (Wi-Fi, Bluetooth, ...) are the bar's popouts, opened inside the same card,
// which morphs to fit them
Scope {
    id: root

    property ShellScreen screen: Quickshell.screens[0]
    property string page: "quick"
    // Kept while the back row fades out
    property string title: ""

    readonly property var titles: ({ network: "Wi-Fi", bluetooth: "Bluetooth", vpn: "VPN", media: "Music effects", power: "Power" })

    Connections {
        target: QuickSettings
        function onOpenChanged() {
            if (!QuickSettings.open)
                return;
            root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
            host.show("quick");
        }
    }

    // Stands in for the bar's Popouts, which the borrowed pages talk to
    Item {
        id: host

        property bool pinned: true
        property bool busy: false
        property bool fx: false
        readonly property Item hitbox: pageArea
        readonly property int corner: card.radius
        signal detailRequested(string name)

        onDetailRequested: name => show(name)

        function show(name) {
            // Before the page switch, so a page that grabs focus keeps it
            keys.forceActiveFocus();
            pinned = true;
            fx = name === "media";
            root.page = name;
            if (name !== "quick")
                root.title = root.titles[name] ?? "";
        }

        function back() {
            show("quick");
        }

        function close() {
            QuickSettings.open = false;
        }
    }

    PanelWindow {
        id: win

        screen: root.screen
        visible: QuickSettings.open || card.opacity > 0

        WlrLayershell.namespace: "quicksettings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: QuickSettings.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // Next time it opens on the main page without morphing from the last one
        onVisibleChanged: if (!visible) root.page = "quick"

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: QuickSettings.open ? 0.3 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: host.close()
        }

        Rectangle {
            id: card

            readonly property bool detail: root.page !== "quick"

            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: pageArea.width
            height: header.height + pageArea.height
            radius: Theme.radius + 6
            color: Qt.alpha(Theme.bg, 0.85)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.25)
            clip: true

            opacity: QuickSettings.open ? 1 : 0
            scale: QuickSettings.open ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: QuickSettings.open ? Easing.OutBack : Easing.InCubic } }
            Behavior on width {
                enabled: win.visible
                NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
            }
            Behavior on height {
                enabled: win.visible
                NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
            }

            // Swallows clicks so they don't reach the close-on-outside-click area
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.BackButton
                onClicked: mouse => {
                    if (mouse.button === Qt.BackButton && card.detail)
                        host.back();
                }
            }

            Item {
                id: keys
                focus: true
                Keys.onEscapePressed: card.detail ? host.back() : host.close()
            }

            // Back row, only above a full page
            Item {
                id: header

                width: parent.width
                height: card.detail ? 48 : 0
                opacity: card.detail ? 1 : 0
                visible: opacity > 0
                Behavior on height { NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                Rectangle {
                    id: backButton

                    x: Theme.pad - 6
                    y: 12
                    width: 32
                    height: 32
                    radius: height / 2
                    color: backMouse.containsMouse ? Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.16)) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Icon {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        font.pixelSize: 20
                        color: backMouse.containsMouse ? Theme.accent : Theme.text
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: host.back()
                    }
                }

                Label {
                    anchors.left: backButton.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: backButton.verticalCenter
                    text: root.title
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            Item {
                id: pageArea

                readonly property Item current: ({ quick: quickPage, network: networkPage, bluetooth: bluetoothPage, vpn: vpnPage, media: mediaPage, power: powerPage })[root.page] ?? quickPage

                y: header.height
                width: current.implicitWidth
                height: current.implicitHeight

                Page { id: quickPage; name: "quick"; QuickSettingsPage { popouts: host; here: parent.here } }
                Page { id: networkPage; name: "network"; NetworkPopout { popouts: host; here: parent.here } }
                Page { id: bluetoothPage; name: "bluetooth"; BluetoothPopout { popouts: host; here: parent.here } }
                Page { id: vpnPage; name: "vpn"; VpnPopout { popouts: host; here: parent.here } }
                Page { id: mediaPage; name: "media"; MediaPopout { popouts: host; here: parent.here } }
                Page { id: powerPage; name: "power"; PowerPopout { popouts: host; here: parent.here } }
            }
        }
    }

    component Page: Item {
        required property string name
        readonly property bool shown: root.page === name
        readonly property bool here: QuickSettings.open && shown

        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        width: implicitWidth
        height: implicitHeight
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: shown ? 1 : 0
        visible: opacity > 0
        enabled: here

        transform: Translate {
            y: shown ? 0 : -12
            Behavior on y { NumberAnimation { duration: Theme.animPanel; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
        }
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }
}
