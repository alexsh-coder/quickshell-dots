//@ pragma UseQApplication
//@ pragma IconTheme Suru++-Extra
//@ pragma Env QT_IMAGEIO_MAXALLOC=2048
import Quickshell
import qs.modules.bar
import qs.modules.clipboard
import qs.modules.cursorfx
import qs.modules.desk
import qs.modules.dock
import qs.modules.launcher
import qs.modules.lock
import qs.modules.media
import qs.modules.musicfx
import qs.modules.notifications
import qs.modules.osd
import qs.modules.overview
import qs.modules.power
import qs.modules.quicksettings
import qs.modules.settings
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

    VideoFx {}

    Variants {
        model: Quickshell.screens

        Scope {
            id: desk
            required property var modelData

            WallpaperTransition { screen: desk.modelData }
            WallpaperFx { screen: desk.modelData }
            VideoGlow { screen: desk.modelData }
            DeskClick { screen: desk.modelData }
            DeskLayer { screen: desk.modelData }
            Dock { screen: desk.modelData }
            CursorFx { screen: desk.modelData }
            CursorKick { screen: desk.modelData }
        }
    }

    Notifications {}
    BatteryAlert {}
    NotificationCenter {}
    Osd {}
    Overview {}
    Launcher {}
    Clipboard {}
    Lock {}
    PowerMenu {}
    MediaShade {}
    WallpaperPicker {}
    DeskEditor {}
    DeskEdge {}
    QuickSettingsCard {}
    SettingsWindow {}
}
