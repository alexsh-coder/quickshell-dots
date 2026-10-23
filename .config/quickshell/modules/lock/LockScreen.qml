import QtQuick
import QtQuick.Effects
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var lock
    property size wallSize
    property string wall

    readonly property color white: Qt.rgba(1, 1, 1, 0.75)
    readonly property color warm: "#ffd38a"
    readonly property bool leaving: lock.unlocking
    readonly property color lineTint: lock.failed ? Theme.urgent : Keyboard.caps ? warm : Theme.accent

    // 0 is the live desktop, 1 is fully sunk into the lock
    property real depth: 0
    onLeavingChanged: if (leaving) outro.start()

    // The first frame draws every layer at 1/255 opacity: shaders compile and blur buffers get
    // allocated there, while nothing is visible yet, instead of stuttering the intro one by one
    property bool primed: false
    readonly property real floor: primed ? 0 : 1 / 255

    FrameAnimation {
        running: !root.primed
        onTriggered: if (currentFrame >= 2) { root.primed = true; if (!root.leaving) intro.start(); }
    }

    NumberAnimation {
        id: intro
        target: root
        property: "depth"
        from: 0
        to: 1
        duration: 1100
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.emphasizedDecel
    }

    NumberAnimation {
        id: outro
        target: root
        property: "depth"
        to: 0
        // Moves right away and lands softly on the desktop, so the hand-off is invisible
        duration: 850
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.standard
    }

    // The wallpaper fades in over the live desktop as if the windows dissolve, then zooms in,
    // blurs and dims; the way out is the reverse, ending on the live desktop again.
    // MultiEffect's blur barely shows below ~0.6 and then rushes in, so rather than animating it,
    // fixed blurs fade in over the sharp copy, which fades out (sharp detail outweighs a blur).
    readonly property real shown: Math.max(floor, Math.min(1, depth / 0.3))

    component Wall: Image {
        anchors.fill: parent
        source: root.wall ? "file://" + root.wall : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize: root.wallSize
    }

    // Covers the desktop even if the wallpaper is missing. It only comes in under the soft blur,
    // which is already opaque by then: fading it along with the wallpaper would dip to dark
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Math.max(0, Math.min(1, (root.depth - 0.5) / 0.2))
        visible: opacity > 0
    }

    Item {
        id: scene
        anchors.fill: parent
        scale: 1 + 0.07 * root.depth

        // Synchronous, so the first frame isn't empty; all three copies share one cached decode
        Wall {
            opacity: root.shown * (1 - Math.max(0, Math.min(1, (root.depth - 0.3) / 0.3)))
            visible: opacity > 0
        }

        // Two effects sharing one source item break each other's blur, so each gets its own copy
        Wall {
            id: wallSoft
            visible: false
        }

        Wall {
            id: wallDeep
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: wallSoft
            visible: opacity > 0 && deep.opacity < 1
            blurEnabled: true
            blur: 1
            blurMax: 20
            brightness: -0.06
            opacity: Math.max(root.floor, Math.min(1, (root.depth - 0.15) / 0.3))
        }

        MultiEffect {
            id: deep
            anchors.fill: parent
            source: wallDeep
            visible: opacity > 0
            blurEnabled: true
            blur: 1
            blurMax: 56
            // Subtractive, so it deepens the darks and shifts hues a little; kept light on purpose
            brightness: -0.2
            saturation: 0.1
            opacity: Math.max(root.floor, Math.min(1, (root.depth - 0.35) / 0.4))
        }

        // The rest of the dimming multiplies, which keeps the colours
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.25 * Math.max(root.floor, Math.min(1, (root.depth - 0.1) / 0.6))
        }
    }

    ShaderEffect {
        anchors.fill: parent
        opacity: Math.max(root.floor, (root.depth - 0.5) / 0.5)

        property real time: root.lock.time
        property real aspect: width / Math.max(1, height)
        property real density: 0.26
        property color tint: Qt.rgba(Theme.accent.r * 0.5 + 0.5, Theme.accent.g * 0.5 + 0.5, Theme.accent.b * 0.5 + 0.5, 0.6)

        fragmentShader: Qt.resolvedUrl("../../shaders/petals.frag.qsb")
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: content
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40 + 50 * (1 - root.depth)
        spacing: 0
        opacity: Math.max(root.floor, (root.depth - 0.45) / 0.55)
        scale: 0.96 + 0.04 * root.depth

        Row {
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: 5

                Digit {
                    required property int index
                    value: Qt.formatTime(clock.date, "hh:mm")[index]
                    color: root.white
                    font.family: Theme.font
                    font.pixelSize: 128
                    font.weight: Font.Light
                    font.features: ({ tnum: 1 })
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleDateString(Qt.locale("en_US"), "dddd, d MMMM yyyy")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 22
            font.weight: Font.Light
        }

        Item { width: 1; height: 40 }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 440
            height: 64

            PasswordLine {
                id: line
                anchors.fill: parent
                lock: root.lock
                count: root.lock.password.length
                tint: root.lineTint

                Behavior on tint { ColorAnimation { duration: 260 } }
            }

            Label {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -22
                text: root.lock.busy ? "Checking…" : root.lock.failed ? "Wrong password" : Keyboard.caps ? "Caps Lock" : "Password"
                color: root.lock.failed ? Theme.urgent : Keyboard.caps ? root.warm : Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 13
                font.weight: Font.Normal
                opacity: root.lock.password && !Keyboard.caps && !root.lock.busy ? 0 : 1

                Behavior on opacity { NumberAnimation { duration: Theme.anim } }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Keyboard.layout || "EN"
            color: layoutArea.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 14

            MouseArea {
                id: layoutArea
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Keyboard.switchTo((Keyboard.index + 1) % Math.max(1, Keyboard.layouts.length))
            }
        }
    }

    NowPlaying {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56 - 30 * (1 - root.depth)
        opacity: content.opacity
    }

    Connections {
        target: root.lock
        function onTyped(sign) {
            line.hit(sign);
        }
        function onRejected() {
            line.shake();
        }
    }

    // Keys come in as text, so either layout types into the field
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        // On resume the seat drops its keyboard and brings it back: Qt deactivates the window,
        // then ignores the new enter for the same surface, so keys go nowhere. Take it back by hand
        Timer {
            interval: 250
            repeat: true
            running: !keys.Window.active
            onTriggered: {
                keys.Window.window?.requestActivate();
                keys.forceActiveFocus();
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.lock.submit();
            else if (event.key === Qt.Key_Backspace)
                root.lock.erase(event.modifiers & Qt.ControlModifier);
            else if (event.key === Qt.Key_Escape)
                root.lock.erase(true);
            else if (event.text && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier)))
                root.lock.input(event.text);
            event.accepted = true;
        }
    }
}
