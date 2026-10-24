import QtQuick
import qs.config
import qs.services

// One widget on the desktop. Its rect glides on a wallpaper or preset switch; a change that can't
// glide (a style, a color) fades it out and back in with the new settings. Appears and leaves fading
Item {
    id: root

    required property string json
    required property bool gone
    property real sw: 1920
    property real sh: 1080

    readonly property var spec: JSON.parse(json)
    // What the content shows: lags behind spec while a swap fades out
    property var cfg: spec
    property real swap: 1
    property real appear: 0
    // The editor's live rect while dragging, saved on release
    readonly property var rect: Desk.preview?.[spec.id] ?? spec
    readonly property bool isVis: spec.type === "visualizer"
    // Visualizers only while music plays, or while their place is being edited
    readonly property bool live: !isVis || Desk.editing || (MusicFx.desktop && Cava.active)
    // Hidden widgets stay in the preset; the editor shows them faintly so they can be found
    readonly property real hide: spec.hidden || !Desk.widgetsOn ? (Desk.editing ? 0.25 : 0) : 1
    property real shown: !gone && live ? hide : 0

    // Settings that can't be interpolated
    function discrete(s) {
        return JSON.stringify(Object.keys(s).filter(k => typeof s[k] !== "number").sort().map(k => [k, s[k]]));
    }

    onSpecChanged: {
        if (Desk.morphing && discrete(spec) !== discrete(cfg))
            swapAnim.restart();
        else if (!swapAnim.running)
            cfg = spec;
    }

    x: (rect.x - rect.w / 2) * sw
    y: (rect.y - rect.h / 2) * sh
    width: rect.w * sw
    height: rect.h * sh
    opacity: appear * swap * shown * (cfg.opacity ?? 1)
    scale: 0.94 + 0.06 * Math.min(appear, shown)
    visible: opacity > 0

    Behavior on x { enabled: Desk.morphing; Glide {} }
    Behavior on y { enabled: Desk.morphing; Glide {} }
    Behavior on width { enabled: Desk.morphing; Glide {} }
    Behavior on height { enabled: Desk.morphing; Glide {} }
    Behavior on shown { NumberAnimation { duration: Desk.morphTime / 2; easing.type: Easing.InOutSine } }

    component Glide: NumberAnimation {
        duration: Desk.morphTime
        easing.type: Easing.InOutSine
    }

    NumberAnimation on appear {
        from: 0
        to: 1
        duration: Desk.morphTime / 2
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: root; property: "swap"; to: 0; duration: Desk.morphTime / 2; easing.type: Easing.InSine }
        ScriptAction { script: root.cfg = root.spec }
        NumberAnimation { target: root; property: "swap"; to: 1; duration: Desk.morphTime / 2; easing.type: Easing.OutSine }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: ({ visualizer: visualizer, clock: clock, calendar: calendar, media: media, weather: weather, stats: stats, lyrics: lyrics })[root.spec.type] ?? null
    }

    Component {
        id: visualizer
        VisualizerWidget {
            cfg: root.cfg
            sh: root.sh
            active: (root.live && root.hide > 0 || root.shown > 0) && !root.gone
        }
    }

    Component {
        id: clock
        ClockWidget { cfg: root.cfg }
    }

    Component {
        id: calendar
        CalendarWidget { cfg: root.cfg }
    }

    Component {
        id: media
        MediaWidget { cfg: root.cfg }
    }

    Component {
        id: weather
        WeatherWidget { cfg: root.cfg }
    }

    Component {
        id: lyrics
        LyricsWidget { cfg: root.cfg }
    }

    Component {
        id: stats
        StatsWidget { cfg: root.cfg }
    }
}
