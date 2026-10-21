import QtQuick
import qs.config
import qs.components
import qs.services

// Shown while a screen recording runs; click stops it
Rectangle {
    id: root

    anchors.verticalCenter: parent.verticalCenter
    visible: Recorder.active
    implicitWidth: row.implicitWidth + 28
    implicitHeight: 30
    radius: height / 2
    color: Theme.surface

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: Recorder.stop()
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.urgent
        opacity: hover.hovered ? 0.12 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            id: dot
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: Theme.urgent

            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                onRunningChanged: if (!running) dot.opacity = 1
                NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const s = Recorder.elapsed;
                const pad = n => String(n).padStart(2, "0");
                return s >= 3600 ? `${Math.floor(s / 3600)}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`
                                 : `${Math.floor(s / 60)}:${pad(s % 60)}`;
            }
        }
    }
}
