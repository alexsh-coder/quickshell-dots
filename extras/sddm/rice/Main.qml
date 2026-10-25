import QtQuick
import QtQuick.Effects
import "components"

// The lockscreen of the shell, rebuilt on SDDM: the wallpaper sinks into blur as the greeter
// comes up, and dissolves to black once the login goes through
Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "black"

    readonly property color accent: config.accent || "#33ccff"
    readonly property color urgent: "#ff6b81"
    readonly property color warm: "#ffd38a"
    readonly property color white: Qt.rgba(1, 1, 1, 0.75)
    readonly property string font: maple.name || "sans-serif"
    readonly property string lightFont: mapleLight.name || font

    property real time: 0
    property real depth: 0
    property string password: ""
    property bool busy: false
    property bool failed: false
    property bool leaving: false

    property var users: []
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    property var sessions: []
    readonly property var user: users[userIndex] ?? { name: userModel.lastUser, realName: "" }
    property bool editingUser: false
    readonly property string userName: user.name
    readonly property bool caps: keyboard.capsLock
    readonly property color lineTint: failed ? urgent : caps ? warm : accent

    FontLoader { id: maple; source: "fonts/MapleMono-Regular.ttf" }
    FontLoader { id: mapleLight; source: "fonts/MapleMono-Light.ttf" }
    FontLoader { source: "fonts/MapleMono-Medium.ttf" }

    Repeater {
        model: userModel
        Item {
            required property int index
            required property string name
            required property string realName
            Component.onCompleted: {
                const u = Array.from(root.users);
                u[index] = { name: name, realName: realName };
                root.users = u;
            }
        }
    }

    Repeater {
        model: sessionModel
        Item {
            required property int index
            required property string name
            Component.onCompleted: {
                const s = Array.from(root.sessions);
                s[index] = name;
                root.sessions = s;
            }
        }
    }

    FrameAnimation {
        running: true
        onTriggered: root.time += frameTime
    }

    Component.onCompleted: intro.start()

    NumberAnimation {
        id: intro
        target: root
        property: "depth"
        from: 0
        to: 1
        duration: 1400
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
    }

    function input(text) {
        if (busy || leaving)
            return;
        failed = false;
        password += text;
        line.hit(1);
    }

    function erase(all) {
        if (busy || leaving || !password)
            return;
        password = all ? "" : password.slice(0, -1);
        line.hit(-1);
    }

    function stepUser(d) {
        if (!users.length)
            return;
        userIndex = (userIndex + d + users.length) % users.length;
        password = "";
        failed = false;
    }

    function editUser(event) {
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape || k === Qt.Key_Down)
            editingUser = false;
        else if (k === Qt.Key_Left)
            stepUser(-1);
        else if (k === Qt.Key_Right || k === Qt.Key_Space)
            stepUser(1);
        else
            return;
        failed = false;
    }

    function submit() {
        if (!password || !userName || busy || leaving)
            return;
        busy = true;
        sddm.login(userName, password, sessionIndex);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.failed = true;
            root.password = "";
            line.shake();
        }
        function onLoginSucceeded() {
            root.busy = false;
            root.leaving = true;
        }
    }

    component Wall: Image {
        anchors.fill: parent
        source: config.background ? Qt.resolvedUrl(config.background) : ""
        fillMode: Image.PreserveAspectCrop
    }

    Item {
        id: scene
        anchors.fill: parent
        scale: 1 + 0.07 * root.depth
        opacity: fade.opacity

        Wall {
            opacity: 1 - Math.max(0, Math.min(1, (root.depth - 0.3) / 0.3))
            visible: opacity > 0
        }

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
            opacity: Math.max(0, Math.min(1, (root.depth - 0.15) / 0.3))
        }

        MultiEffect {
            id: deep
            anchors.fill: parent
            source: wallDeep
            visible: opacity > 0
            blurEnabled: true
            blur: 1
            blurMax: 56
            brightness: -0.2
            saturation: 0.1
            opacity: Math.max(0, Math.min(1, (root.depth - 0.35) / 0.4))
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.25 * Math.max(0, Math.min(1, (root.depth - 0.1) / 0.6))
        }

        ShaderEffect {
            anchors.fill: parent
            opacity: Math.max(0, (root.depth - 0.5) / 0.5)

            property real time: root.time
            property real aspect: width / Math.max(1, height)
            property real density: 0.26
            property color tint: Qt.rgba(root.accent.r * 0.5 + 0.5, root.accent.g * 0.5 + 0.5, root.accent.b * 0.5 + 0.5, 0.6)

            fragmentShader: Qt.resolvedUrl("shaders/petals.frag.qsb")
        }
    }

    // Everything fades to black on the way into the session
    QtObject {
        id: fade
        property real opacity: root.leaving ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    }

    Column {
        id: content
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40 + 50 * (1 - root.depth)
        spacing: 0
        opacity: Math.max(0, (root.depth - 0.45) / 0.55) * fade.opacity
        scale: 0.96 + 0.04 * root.depth

        Row {
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: 5

                Digit {
                    required property int index
                    value: Qt.formatTime(clock.date, "hh:mm")[index]
                    color: root.white
                    font.family: root.lightFont
                    font.pixelSize: 128
                    font.weight: Font.Light
                    font.features: ({ tnum: 1 })
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleDateString(Qt.locale("en_US"), "dddd, d MMMM yyyy")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: root.lightFont
            font.pixelSize: 22
            font.weight: Font.Light
        }

        Item { width: 1; height: 36 }

        // Login: Tab and Shift+Tab move between it and the password, arrows step through the accounts
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 440
            height: 30

            Row {
                anchors.centerIn: parent
                spacing: 8

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_left"
                    font.pixelSize: 18
                    color: Qt.rgba(1, 1, 1, 0.45)
                    opacity: root.editingUser && root.users.length > 1 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }

                Text {
                    id: nameText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.userName
                    color: root.editingUser || userArea.containsMouse ? root.accent : Qt.rgba(1, 1, 1, 0.7)
                    font.family: root.font
                    font.pixelSize: 16
                    Behavior on color { ColorAnimation { duration: 220 } }
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_right"
                    font.pixelSize: 18
                    color: Qt.rgba(1, 1, 1, 0.45)
                    opacity: root.editingUser && root.users.length > 1 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }
            }

            MouseArea {
                id: userArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editingUser = !root.editingUser
            }
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 440
            height: 48

            PasswordLine {
                id: line
                anchors.fill: parent
                time: root.time
                count: root.password.length
                tint: root.editingUser ? Qt.rgba(1, 1, 1, 0.35) : root.lineTint

                Behavior on tint { ColorAnimation { duration: 260 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: root.editingUser = false
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.busy ? "Checking…" : root.failed ? "Wrong password" : root.caps ? "Caps Lock" : "Password"
            color: root.failed ? root.urgent : root.caps ? root.warm : Qt.rgba(1, 1, 1, 0.45)
            font.family: root.font
            font.pixelSize: 13
            opacity: root.password && !root.caps && !root.busy && !root.failed ? 0 : 1

            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
    }

    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 28
        opacity: content.opacity
        spacing: 18

        component Pick: Text {
            signal clicked
            color: area.containsMouse ? root.accent : Qt.rgba(1, 1, 1, 0.5)
            font.family: root.font
            font.pixelSize: 14
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.clicked()
            }
        }

        Pick {
            text: (root.sessions[root.sessionIndex] ?? "").replace(/ \(.*\)$/, "")
            visible: root.sessions.length > 0
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length
        }

        Pick {
            readonly property var layouts: keyboard.layouts
            text: (layouts[keyboard.currentLayout]?.shortName ?? "us").toUpperCase()
            visible: layouts.length > 1
            onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % layouts.length
        }
    }

    PowerRow {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48 - 30 * (1 - root.depth)
        opacity: content.opacity
        accent: root.accent
        font: root.font
    }

    Timer {
        id: clock
        property date date: new Date()
        interval: 1000
        repeat: true
        running: true
        onTriggered: date = new Date()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onPressed: event => {
            event.accepted = true;
            if (event.key === Qt.Key_Up && !root.editingUser) {
                root.editingUser = true;
                return;
            }
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.editingUser = !root.editingUser;
                return;
            }
            if (root.editingUser) {
                root.editUser(event);
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.submit();
            else if (event.key === Qt.Key_Backspace)
                root.erase(event.modifiers & Qt.ControlModifier);
            else if (event.key === Qt.Key_Escape)
                root.erase(true);
            else if (event.text && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier)))
                root.input(event.text);
            event.accepted = true;
        }
    }
}
