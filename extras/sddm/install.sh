#!/usr/bin/env bash
# Installs the Rice SDDM theme, or re-syncs it with the current wallpaper and accent.
# Usage: install.sh [--enable]   (--enable also makes it the active SDDM theme)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
shell=$(readlink -f "$HOME/.config/quickshell")
dest=/usr/share/sddm/themes/rice
stage=$(mktemp -d)
trap 'rm -rf "${stage:?}"' EXIT

cp -r "$here/rice/." "$stage/"
mkdir -p "$stage/shaders" "$stage/fonts"
cp "$shell/shaders/petals.frag.qsb" "$shell/shaders/wave.frag.qsb" "$stage/shaders/"

# SDDM runs as its own user and can't see fonts in ~/.local/share/fonts
for w in Regular Light Medium; do
    f=$(fc-list : file | grep -m1 "MapleMono-$w.ttf" | cut -d: -f1 || true)
    [ -n "$f" ] && cp "$f" "$stage/fonts/"
done

# The wallpaper awww shows now (or the still of a video one), and the accent the shell picked from it
wall=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1 || true)
[ -f "$wall" ] && magick "$wall" -resize '2560x2560>' -quality 92 "$stage/background.jpg"
accent=$(cat "$(ls -t "$HOME"/.local/state/quickshell/by-shell/*/accent 2>/dev/null | head -1)" 2>/dev/null | grep -om1 '#[0-9a-fA-F]\{6\}' || true)
[ -n "$accent" ] && sed -i "s/^accent=.*/accent=$accent/" "$stage/theme.conf"

sudo rm -rf "${dest:?}"
sudo cp -r "$stage" "$dest"
sudo chmod -R a+rX "$dest"

# Lets the shell re-sync the wallpaper and accent on its own
sudo install -m 755 "$here/sddm-rice-sync" /usr/local/bin/sddm-rice-sync
sudo install -m 440 "$here/sudoers" /etc/sudoers.d/sddm-rice
sudo visudo -cf /etc/sudoers.d/sddm-rice >/dev/null

# The greeter runs on Xorg at the panel's real pixels; scale it like the Wayland session so the text matches the lockscreen
scale=$(sed -n 's/.*\["scale"\] = \([0-9.]*\).*/\1/p' "$HOME/.config/hypr/settings.lua" 2>/dev/null | head -1)
printf '[General]\nGreeterEnvironment=QT_SCALE_FACTOR=%s\n' "${scale:-1}" | sudo tee /etc/sddm.conf.d/greeter.conf >/dev/null

if [ "${1:-}" = --enable ]; then
    printf '[Theme]\nCurrent=rice\n' | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
fi
echo "Installed to $dest"
