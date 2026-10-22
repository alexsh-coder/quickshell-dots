import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.config

// System tray, icons turned symbolic in the accent (see tint.frag). Click activates, middle click is the secondary
// action, right click opens the app's menu, wheel scrolls.
Row {
    id: root

    readonly property int count: SystemTray.items.values.length
    // Apps that only send pixmaps, mapped to their panel icon
    readonly property var panelNames: ({ TelegramDesktop: "telegram-panel" })
    // Apps shown with their icon from the main theme instead of Papirus
    readonly property var themeNames: ({ "spotify-client": "spotify-launcher" })

    // Papirus ships monochrome icons drawn for trays; anything it lacks falls back to the app's own icon
    function panelIcon(item) {
        if (themeNames[item.id])
            return Quickshell.iconPath(themeNames[item.id]);
        const themed = item.icon.startsWith("image://icon/") ? item.icon.slice(13).split("?")[0] : "";
        const name = panelNames[item.id] ?? themed;
        return name && !name.startsWith("/") ? `file:///usr/share/icons/Papirus/22x22/panel/${name}.svg` : "";
    }

    spacing: 12
    anchors.verticalCenter: parent.verticalCenter

    Repeater {
        model: SystemTray.items

        Item {
            id: entry

            required property SystemTrayItem modelData

            property bool fallback: false

            implicitWidth: 22
            implicitHeight: 22
            anchors.verticalCenter: parent.verticalCenter

            // The layer sits on the full cell, so whatever its rounding to whole pixels clips is empty margin
            Item {
                id: icon
                anchors.fill: parent
                scale: mouse.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }

                layer.enabled: true
                layer.effect: ShaderEffect {
                    property color color: Theme.barAccent
                    Behavior on color { ColorAnimation { duration: Theme.anim } }
                    fragmentShader: Qt.resolvedUrl("../../shaders/tint.frag.qsb")
                }

                Image {
                    anchors.fill: parent
                    // Theme icons fill their canvas, Papirus panel ones leave a margin
                    anchors.margins: root.themeNames[entry.modelData.id] && !entry.fallback ? 2 : 0
                    source: entry.fallback ? entry.modelData.icon : root.panelIcon(entry.modelData) || entry.modelData.icon
                    onStatusChanged: if (status === Image.Error && !entry.fallback) entry.fallback = true
                    sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            QsMenuAnchor {
                id: menu
                menu: entry.modelData.menu
                anchor.item: entry
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                // Shifted down so the menu opens from the bar's bottom edge
                anchor.rect.y: (Theme.barHeight - entry.height) / 2
                anchor.rect.width: entry.width
                anchor.rect.height: entry.height
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                anchors.margins: -6
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: event => {
                    const item = entry.modelData;
                    if (event.button === Qt.RightButton || item.onlyMenu && event.button === Qt.LeftButton) {
                        if (item.hasMenu)
                            menu.open();
                    } else if (event.button === Qt.MiddleButton) {
                        item.secondaryActivate();
                    } else {
                        item.activate();
                    }
                }
                onWheel: wheel => {
                    const horizontal = wheel.angleDelta.x !== 0;
                    entry.modelData.scroll(horizontal ? wheel.angleDelta.x : wheel.angleDelta.y, horizontal);
                }
            }
        }
    }
}
