import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Region picker for scripts/screenshot.sh: the screen dims, the window under the cursor
// opens up in its own rounded shape; click takes it, drag takes a free region.
// The pick ("x,y wxh" in layout coords, empty if cancelled) is written to the given file
Scope {
    id: root

    property bool shown: false
    property string out: ""
    // [{ x, y, w, h }] in layout coords, topmost first
    property var boxes: []
    readonly property int radius: Settings.get("rounding")

    function finish(geom) {
        if (!shown)
            return;
        shown = false;
        result = geom;
        // A frame for the overlay to leave the screen before grim shoots it
        writeTimer.restart();
    }

    property string result: ""

    Timer {
        id: writeTimer
        interval: 60
        onTriggered: Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"", "sh", root.result, root.out])
    }

    IpcHandler {
        target: "screenshot"

        // boxes: "x,y wxh" lines, as scripts/window-boxes.sh prints them
        function pick(out: string, boxes: string): void {
            root.boxes = boxes.split("\n").filter(l => l).map(l => {
                const [p, s] = l.split(" ");
                const [x, y] = p.split(",").map(Number);
                const [w, h] = s.split("x").map(Number);
                return { x, y, w, h };
            });
            root.out = out;
            root.result = "";
            root.shown = true;
        }
        function cancel(): void {
            root.finish("");
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData
            visible: root.shown

            WlrLayershell.namespace: "screenshot"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            // The box under the cursor, or the drag, in this screen's coords
            property var hover: null
            property point start
            property bool dragging: false
            readonly property var hole: dragging ? drag : hover
            property var drag: ({ x: 0, y: 0, w: 0, h: 0 })
            readonly property real holeRadius: !hole || dragging || hole.w >= width && hole.h >= height ? 0 : root.radius

            function boxAt(px, py) {
                const gx = px + modelData.x, gy = py + modelData.y;
                const b = root.boxes.find(b => gx >= b.x && gx < b.x + b.w && gy >= b.y && gy < b.y + b.h);
                return b ? { x: b.x - modelData.x, y: b.y - modelData.y, w: b.w, h: b.h } : null;
            }

            function geom(b) {
                return `${Math.round(b.x + modelData.x)},${Math.round(b.y + modelData.y)} ${Math.round(b.w)}x${Math.round(b.h)}`;
            }

            onVisibleChanged: {
                dragging = false;
                hover = visible ? boxAt(mouse.mouseX, mouse.mouseY) : null;
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.finish("")

                opacity: root.shown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Shape {
                    anchors.fill: parent

                    ShapePath {
                        fillColor: "#66000000"
                        strokeColor: "transparent"
                        fillRule: ShapePath.OddEvenFill

                        PathRectangle { width: win.width; height: win.height }
                        PathRectangle {
                            x: win.hole?.x ?? 0
                            y: win.hole?.y ?? 0
                            width: win.hole?.w ?? 0
                            height: win.hole?.h ?? 0
                            radius: win.holeRadius
                        }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: win.hole ? Theme.accent : "transparent"
                        strokeWidth: 2

                        PathRectangle {
                            x: (win.hole?.x ?? 0) + 1
                            y: (win.hole?.y ?? 0) + 1
                            width: Math.max(0, (win.hole?.w ?? 0) - 2)
                            height: Math.max(0, (win.hole?.h ?? 0) - 2)
                            radius: Math.max(0, win.holeRadius - 1)
                        }
                    }
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor

                onPositionChanged: m => {
                    if (pressed && !win.dragging && Math.hypot(m.x - win.start.x, m.y - win.start.y) > 4)
                        win.dragging = true;
                    if (win.dragging)
                        win.drag = {
                            x: Math.min(m.x, win.start.x), y: Math.min(m.y, win.start.y),
                            w: Math.abs(m.x - win.start.x), h: Math.abs(m.y - win.start.y)
                        };
                    else
                        win.hover = win.boxAt(m.x, m.y);
                }
                onPressed: m => {
                    if (m.button === Qt.RightButton)
                        root.finish("");
                    else
                        win.start = Qt.point(m.x, m.y);
                }
                onReleased: m => {
                    if (m.button !== Qt.LeftButton || !root.shown)
                        return;
                    if (win.dragging)
                        root.finish(win.drag.w >= 1 && win.drag.h >= 1 ? win.geom(win.drag) : "");
                    else {
                        const b = win.boxAt(m.x, m.y);
                        root.finish(b ? win.geom(b) : "");
                    }
                }
            }
        }
    }
}
