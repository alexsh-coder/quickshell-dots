# quickshell-dots

A Hyprland desktop built around [Quickshell](https://quickshell.org): bar, launcher,
notifications, OSD, lockscreen and music effects are all one QML shell. The accent
colour follows the wallpaper and is pushed out to Hyprland borders, kitty, GTK and
Qt/KDE apps.

## What's inside

- **Bar** in pill groups: workspaces, audio visualizer, tray, clock, network,
  Bluetooth, battery, layout, screen recording indicator. Each pill opens a popout
  on hover.
- **Quick settings** card (`Super+I`): volume, mic and brightness sliders, Wi-Fi,
  Bluetooth, VPN, do not disturb, night light, caffeine, dark mode, power profile,
  visualizer and lyrics toggles.
- **Launcher** (`Super+R`): pinned apps you can drag to reorder, hiding and
  renaming apps, right-click menu.
- **Overview** (`Super+Tab`): windows spin around a ring.
- **Notifications**: toasts and a notification center that slides in from the
  right edge (`Super+N`).
- **OSD** for volume, brightness, mic, layout, Caps Lock and night mode. It stays
  quiet while a panel already shows the same level.
- **Lockscreen** over the blurred wallpaper with the playing track (`Super+L`).
- **Clipboard history** picker (`Super+V`), pastes into the focused window on Enter.
- **Wallpaper picker** (`Super+Shift+W`) for images and looping video wallpapers.
- **Music effects**: desktop visualizers, wallpaper effects driven by the beat,
  synced desktop lyrics with a karaoke glow on the sung word.
- **Light/dark scheme** toggle (`Super+Shift+D`), applied to GTK and Qt apps too.

## Layout

```
.config/hypr/         Hyprland (Lua config), hypridle, hyprlock, helper scripts
.config/quickshell/   the shell: shell.qml, modules/, services/, components/
.config/fastfetch/    fastfetch config
.local/bin/pixfetch   fastfetch with a random pixel-art logo
```

## Requirements

Arch Linux is what it runs on; other distros should work with the same programs.

- Hyprland with Lua config support (0.56+), hypridle, hyprlock, hyprsunset,
  hyprpolkitagent, hyprpicker
- quickshell (`quickshell-git`)
- awww and mpvpaper for wallpapers, ffmpeg for video posters
- matugen for the colour scheme
- cava, playerctl
- cliphist, wl-clipboard
- brightnessctl
- grim, slurp, imagemagick, gpu-screen-recorder for screenshots and recordings
- kitty
- python with PyGObject (Spotify like button over AT-SPI)
- fonts: Maple Mono, CaskaydiaCove Nerd Font, Material Symbols Rounded,
  Noto Color Emoji
- icon theme: Suru++ Asprómauros

The VPN popout talks to a `vpn` helper for sing-box that is not part of this repo.

## Install

Back up your own configs first, then link these in place:

```sh
git clone https://github.com/alexsh-coder/quickshell-dots ~/dotfiles
ln -s ~/dotfiles/.config/hypr       ~/.config/hypr
ln -s ~/dotfiles/.config/quickshell ~/.config/quickshell
ln -s ~/dotfiles/.config/fastfetch  ~/.config/fastfetch
cp ~/.config/hypr/hardware.lua.example ~/.config/hypr/hardware.lua
```

`hardware.lua` holds per-machine settings (monitor scale, mouse, extra env) and is
not tracked. Wallpapers are read from `~/Pictures/Wallpapers` and video wallpapers
from `~/Videos/Wallpapers`.

Hyprland starts `qs` on login. Quickshell reloads itself when a file changes.

## Keys

Caps Lock switches between the English and Russian layouts, Shift+Caps Lock is the
real Caps Lock.

| Keys | Action |
| --- | --- |
| `Super+R` | launcher |
| `Super+T` | terminal |
| `Super+E` | file manager |
| `Super+I` | quick settings |
| `Super+N` | notification center |
| `Super+V` | clipboard history |
| `Super+Tab` | overview |
| `Super+L` | lock |
| `Super+M` / `Super+Shift+M` | music scratchpad / media popout |
| `Super+Shift+W` | wallpaper picker |
| `Super+Shift+D` | light/dark scheme |
| `Super+Shift+N` | night mode |
| `Super+S` / `Super+Shift+S` | scratchpad / move window there |
| `Super+1..0` / `Super+Shift+1..0` | workspace / move window |
| `Super+[` / `Super+]` | previous / next workspace |
| `Super+G` | group windows into tabs |
| `Super+F` / `Super+Space` | fullscreen / float |
| `Super+Q` / `Super+Shift+Q` | close / kill window |
| `Print` / `Super+Print` | screenshot of a window or region / whole screen |
| `Shift+Print` | start or stop screen recording |
| `Ctrl+Alt+Delete` | power menu |
