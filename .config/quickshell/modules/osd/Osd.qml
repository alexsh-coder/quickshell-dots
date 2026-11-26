import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    property bool shown: false
    property string kind: ""
    property string icon: ""
    property string text: ""
    property real value: 0
    property bool dim: false
    property bool glide: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property MprisPlayer player: Players.music.find(p => p.isPlaying) ?? Players.music[0] ?? null

    // Pipewire reports a burst of changes on startup and when the default device switches
    property bool armed: false
    onSinkChanged: rearm()
    onSourceChanged: rearm()
    function rearm() {
        armed = false;
        armDelay.restart();
    }

    function present(kind) {
        if (!shown)
            pop.restart();
        // Glide only when the bar already shows this value, so switching kinds doesn't slide
        glide = shown && kind === root.kind;
        root.kind = kind;
        shown = true;
        hideDelay.restart();
    }

    function showBar(kind, icon, value, dim) {
        present(kind);
        root.icon = icon;
        root.value = value;
        root.dim = dim;
    }

    function showText(icon, text) {
        present("text");
        root.icon = icon;
        root.text = text;
        root.dim = false;
    }

    function showVolume() {
        const a = sink?.audio;
        if (!a)
            return;
        const icon = a.muted || a.volume === 0 ? "volume_off"
                   : a.volume < 0.34 ? "volume_mute"
                   : a.volume < 0.67 ? "volume_down"
                   : "volume_up";
        showBar("volume", icon, a.volume, a.muted);
    }

    function showMic() {
        const a = source?.audio;
        if (a)
            showBar("mic", a.muted ? "mic_off" : "mic", a.volume, a.muted);
    }

    function showMedia() {
        if (!player)
            return;
        const title = [player.trackArtist, player.trackTitle].filter(s => s).join(" — ");
        showText(player.isPlaying ? "play_arrow" : "pause", title || player.identity);
    }

    function stepVolume(a, delta) {
        a.muted = false;
        a.volume = Math.max(0, Math.min(1, Math.round(a.volume * 20) / 20 + delta));
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    Connections {
        target: root.sink?.audio ?? null
        enabled: root.armed && !OsdGate.volume
        function onVolumesChanged() { root.showVolume(); }
        function onMutedChanged() { root.showVolume(); }
    }

    Connections {
        target: root.source?.audio ?? null
        enabled: root.armed && !OsdGate.mic
        function onMutedChanged() { root.showMic(); }
    }

    Connections {
        target: Brightness
        enabled: !OsdGate.brightness
        function onStepped() { root.showBar("brightness", "light_mode", Brightness.value, false); }
    }

    Connections {
        target: NightMode
        function onSwitched() {
            root.showText(NightMode.enabled ? "bedtime" : "bedtime_off",
                          NightMode.enabled ? "Night mode on" : "Night mode off");
        }
    }

    Connections {
        target: Caffeine
        function onSwitched() {
            root.showText("coffee", Caffeine.enabled ? "Caffeine on" : "Caffeine off");
        }
    }

    Connections {
        target: Keyboard
        function onLayoutSwitched() { root.showText("keyboard", Keyboard.layout); }
        function onCapsToggled() { root.showText("keyboard_capslock", Keyboard.caps ? "Caps on" : "Caps off"); }
    }

    IpcHandler {
        target: "osd"

        function volume(action: string): void {
            const a = root.sink?.audio;
            if (!a)
                return;
            if (action === "raise")
                root.stepVolume(a, 0.05);
            else if (action === "lower")
                root.stepVolume(a, -0.05);
            else if (action === "mute")
                a.muted = !a.muted;
            root.showVolume();
        }

        function mic(action: string): void {
            const a = root.source?.audio;
            if (a && action === "mute")
                a.muted = !a.muted;
            root.showMic();
        }

        function brightness(action: string): void {
            if (action === "raise")
                Brightness.raise();
            else if (action === "lower")
                Brightness.lower();
        }

        function media(action: string): void {
            const p = root.player;
            if (!p)
                return;
            if (action === "next" && p.canGoNext)
                p.next();
            else if (action === "prev" && p.canGoPrevious)
                p.previous();
            else if (action === "play-pause" && p.canTogglePlaying)
                p.togglePlaying();
            // The player needs a moment to publish the new track / state
            mediaDelay.restart();
        }

        function caps(): void {
            Keyboard.checkCaps();
        }
    }

    Timer {
        id: armDelay
        interval: 1000
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideDelay
        interval: 900
        onTriggered: root.shown = false
    }

    Timer {
        id: mediaDelay
        interval: 250
        onTriggered: root.showMedia()
    }

    PanelWindow {
        visible: root.shown
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.namespace: "osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors.bottom: true
        margins.bottom: Theme.osdMargin

        implicitWidth: pill.width
        implicitHeight: pill.height
        color: "transparent"
        mask: Region {}

        Rectangle {
            id: pill

            readonly property bool bar: root.kind !== "text"

            width: content.implicitWidth + 36
            height: 48
            radius: height / 2
            color: Qt.alpha(Theme.bg, 0.85)

            Row {
                id: content
                anchors.centerIn: parent
                spacing: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icon
                    font.pixelSize: 24
                    color: root.dim ? Theme.subtext : Theme.accent
                }

                Rectangle {
                    id: track
                    visible: pill.bar
                    anchors.verticalCenter: parent.verticalCenter
                    width: 160
                    height: 6
                    radius: 3
                    color: Theme.muted

                    property real shownValue: root.value
                    Behavior on shownValue {
                        enabled: root.glide
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, track.shownValue))
                        height: parent.height
                        radius: parent.radius
                        color: root.dim ? Theme.subtext : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }
                }

                Label {
                    id: valueLabel
                    visible: pill.bar
                    anchors.verticalCenter: parent.verticalCenter
                    width: valueMetrics.width
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(track.shownValue * 100)
                    color: root.dim ? Theme.subtext : Theme.text

                    TextMetrics {
                        id: valueMetrics
                        font: valueLabel.font
                        text: "100"
                    }
                }

                Label {
                    visible: !pill.bar
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 420)
                    elide: Text.ElideRight
                    text: root.text
                }
            }

            transform: Scale {
                id: popScale
                origin.x: pill.width / 2
                origin.y: pill.height / 2
            }

            NumberAnimation {
                id: pop
                target: popScale
                properties: "xScale,yScale"
                from: 0.9
                to: 1
                duration: Theme.anim
                easing.type: Easing.OutBack
            }
        }
    }
}
