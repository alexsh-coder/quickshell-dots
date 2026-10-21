pragma Singleton

import QtQuick
import Quickshell

// Panels that already show a level on screen keep the OSD from repeating it
Singleton {
    // The bar's volume popout is open
    property bool volumePanel: false

    readonly property bool volume: volumePanel || QuickSettings.open
    readonly property bool mic: QuickSettings.open
    readonly property bool brightness: QuickSettings.open
}
