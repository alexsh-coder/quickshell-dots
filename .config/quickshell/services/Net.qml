pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    readonly property var wifiDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    // Adapter the network popout follows, by interface name
    property alias wifiName: state.wifi
    // Fall back to a connected adapter, then to the first one
    readonly property var wifi: wifiDevices.find(d => d.name === wifiName)
        ?? wifiDevices.find(d => d.connected)
        ?? wifiDevices[0]
        ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    // The connected network, on whichever adapter carries it
    readonly property var active: {
        for (const d of wifiDevices)
            for (const n of d.networks.values)
                if (n.connected)
                    return n;
        return null;
    }
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

    FileView {
        path: Quickshell.statePath("network.json")
        // Load synchronously so the first open after a restart already sees the adapter
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: state
            property string wifi: ""
        }
    }
}
