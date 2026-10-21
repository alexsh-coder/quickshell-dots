import Quickshell
import qs.modules.bar
import qs.modules.clipboard
import qs.modules.launcher
import qs.modules.lock
import qs.modules.lyrics
import qs.modules.musicfx
import qs.modules.notifications
import qs.modules.osd
import qs.modules.wallpaper

// 

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: desk
            required property var modelData

            WallpaperFx { screen: desk.modelData }
            DesktopVisualizer { screen: desk.modelData }
        }
    }

    DesktopLyrics {
        screen: Quickshell.screens[0]
    }

    Notifications {}
    Osd {}
    Launcher {}
    Clipboard {}
    Lock {}
    WallpaperPicker {}
}
