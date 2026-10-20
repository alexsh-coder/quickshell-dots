pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var active: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property bool ethernet: wired?.connected ?? false
    readonly property bool wifiOn: Networking.wifiEnabled

    // nf-md wifi_strength_outline, 1..4
    readonly property var levels: ["\u{f092f}", "\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"]

    function glyph(strength) {
        return levels[Math.max(0, Math.min(4, Math.ceil(strength * 4)))];
    }

    readonly property string icon: ethernet ? "\u{f0200}"
        : !wifiOn ? "\u{f05aa}"
        : active ? glyph(active.signalStrength)
        : "\u{f092e}"

    function secured(net) {
        return net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Owe;
    }

    function enterprise(net) {
        return net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap
            || net.security === WifiSecurityType.Wpa3SuiteB192;
    }
}
