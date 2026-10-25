import QtQuick


// Typed characters show up as ripples on a line instead of dots
Item {
    id: root

    property real time: 0
    property color tint: "white"
    property int count: 0

    property var hits: [-100, -100, -100, -100, -100, -100, -100, -100]
    property var signs: [0, 0, 0, 0, 0, 0, 0, 0]
    property int slot: 0

    function hit(sign) {
        const h = Array.from(hits), s = Array.from(signs);
        h[slot] = time;
        s[slot] = sign;
        slot = (slot + 1) % 8;
        hits = h;
        signs = s;
    }

    function shake() {
        shaker.restart();
    }

    ShaderEffect {
        id: fx
        width: parent.width
        height: parent.height

        property real time: root.time
        property real aspect: width / Math.max(1, height)
        property real pixel: 1 / Math.max(1, height)
        property real reach: 0.16 + Math.min(root.count, 14) * 0.024
        property color tint: root.tint
        property vector4d hitsA: Qt.vector4d(root.hits[0], root.hits[1], root.hits[2], root.hits[3])
        property vector4d hitsB: Qt.vector4d(root.hits[4], root.hits[5], root.hits[6], root.hits[7])
        property vector4d signsA: Qt.vector4d(root.signs[0], root.signs[1], root.signs[2], root.signs[3])
        property vector4d signsB: Qt.vector4d(root.signs[4], root.signs[5], root.signs[6], root.signs[7])

        Behavior on reach { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }

        fragmentShader: Qt.resolvedUrl("../shaders/wave.frag.qsb")
    }

    SequentialAnimation {
        id: shaker
        loops: 1
        NumberAnimation { target: fx; property: "x"; to: 14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: fx; property: "x"; to: -11; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: fx; property: "x"; to: 7; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: fx; property: "x"; to: -3; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: fx; property: "x"; to: 0; duration: 90; easing.type: Easing.OutQuad }
    }
}
