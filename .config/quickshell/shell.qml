import Quickshell
import qs.modules.bar
import qs.modules.launcher
import qs.modules.osd

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    Osd {}
    Launcher {}
}
