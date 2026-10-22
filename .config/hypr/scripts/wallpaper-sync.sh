#!/usr/bin/env bash
# Mirror the current desktop wallpaper to a location the sddm user can read
# (/home/lab-qs is 700). The sugar-candy theme's Backgrounds/custom/current.jpg
# is a symlink to $DEST. Usage: wallpaper-sync.sh [path]  (default: ask awww)
DEST=/var/lib/wallpaper-sync/current

src=${1:-$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1)}
src=${src/#\~/$HOME}
[ -f "$src" ] || exit 0

# Skip the copy if it's already the same image.
cmp -s "$src" "$DEST" && exit 0
cp "$src" "$DEST.tmp" && chmod 644 "$DEST.tmp" && mv -f "$DEST.tmp" "$DEST"
