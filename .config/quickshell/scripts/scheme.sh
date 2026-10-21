#!/usr/bin/env bash
# Propagates the shell's light/dark scheme to GTK, Qt/KDE apps and the
# xdg portal (Telegram, Firefox/Zen, libadwaita follow the portal).
# Usage: scheme.sh light|dark
set -u
mode=${1:-dark}
if [ "$mode" = light ]; then
    pref=prefer-light gtk=Breeze icons=Tela-circle-light dark=false
else
    pref=prefer-dark gtk=Breeze-Dark icons=Tela-circle-dark dark=true
fi

has() { command -v "$1" >/dev/null 2>&1; }

if has gsettings; then
    gsettings set org.gnome.desktop.interface color-scheme "$pref"
    gsettings set org.gnome.desktop.interface gtk-theme "$gtk"
    gsettings set org.gnome.desktop.interface icon-theme "$icons"
fi

for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    [ -f "$f" ] || continue
    sed -i -e "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$dark/" \
           -e "s/^gtk-theme-name=.*/gtk-theme-name=$gtk/" \
           -e "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$icons/" "$f"
done

# The KDE color scheme is applied by services/Accent.qml, together with the accent
if has kwriteconfig6; then
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "$icons"
    has dbus-send && dbus-send --session --type=signal /KIconLoader \
        org.kde.KIconLoader.iconChanged int32:0
fi
