import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config

// App icon recoloured into the accent (see appicon.frag), so every icon theme reads as one set
IconImage {
    id: root

    property string icon
    property color color: Theme.accent
    property color base: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.22))

    source: Quickshell.iconPath(icon, "application-x-executable")

    ShaderEffectSource {
        id: iconTex
        sourceItem: root.backer
        hideSource: true
        visible: false
    }

    // The dominant colour is worked out once per icon in a single pixel, not for every pixel
    ShaderEffect {
        id: stats
        width: 1
        height: 1
        blending: false
        property var source: iconTex
        fragmentShader: Qt.resolvedUrl("../shaders/appicon-stats.frag.qsb")
    }

    ShaderEffectSource {
        id: statsTex
        sourceItem: stats
        hideSource: true
        visible: false
        smooth: false
    }

    ShaderEffect {
        anchors.fill: parent
        property var source: iconTex
        property var stats: statsTex
        property color color: root.color
        property color base: root.base
        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Behavior on base { ColorAnimation { duration: Theme.anim } }
        fragmentShader: Qt.resolvedUrl("../shaders/appicon.frag.qsb")
    }
}
