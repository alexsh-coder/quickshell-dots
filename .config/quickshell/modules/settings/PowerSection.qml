import QtQuick
import qs.config
import qs.components
import qs.services

Column {
    id: root

    property bool shown: false

    spacing: 6

    SectionTitle { text: "Battery" }

    SettingRow {
        setting: "ecoOnBattery"
        label: "Battery saver"
        hint: Settings.hasBattery ? "Turns blur and shadows off while unplugged" + (Settings.eco ? " · on now" : "")
            : "Turns blur and shadows off while unplugged · no battery found"
        Toggle {
            checked: Settings.ecoOnBattery
            onToggled: Settings.ecoOnBattery = !checked
        }
    }
}
