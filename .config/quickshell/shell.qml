import Quickshell
import qs.modules.bar
import qs.modules.launcher
import qs.modules.lyrics
import qs.modules.osd
import qs.modules.wallpaper

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    DesktopLyrics {
        screen: Quickshell.screens[0]
    }

    Osd {}
    Launcher {}
    WallpaperPicker {}
}
