import QtQuick

// One clock digit: the old value lifts away as the new one rises in
Item {
    id: root

    property string value
    property alias font: now.font
    property color color: "white"
    readonly property real travel: height * 0.32

    implicitWidth: metrics.advanceWidth
    implicitHeight: now.implicitHeight

    TextMetrics {
        id: metrics
        font: now.font
        text: "0"
    }

    onValueChanged: {
        if (now.text === value)
            return;
        old.text = now.text;
        now.text = value;
        if (old.text)
            flip.restart();
    }

    Text {
        id: old
        anchors.horizontalCenter: parent.horizontalCenter
        font: now.font
        color: root.color
        opacity: 0
    }

    Text {
        id: now
        anchors.horizontalCenter: parent.horizontalCenter
        color: root.color
    }

    ParallelAnimation {
        id: flip
        NumberAnimation { target: old; property: "y"; from: 0; to: -root.travel; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1] }
        NumberAnimation { target: old; property: "opacity"; from: 1; to: 0; duration: 320 }
        NumberAnimation { target: now; property: "y"; from: root.travel; to: 0; duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1] }
        NumberAnimation { target: now; property: "opacity"; from: 0; to: 1; duration: 500 }
    }
}
