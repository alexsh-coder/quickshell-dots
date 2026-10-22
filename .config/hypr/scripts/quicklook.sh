#!/usr/bin/env bash
# macOS-QuickLook-style file preview, invoked by the "Quick Look" Dolphin
# service menu (~/.local/share/kio/servicemenus/quicklook.desktop) with the
# selected file's path as $1. Bound to Space inside Dolphin only, via
# Dolphin's own Configure Keyboard Shortcuts dialog -- not a Hyprland bind,
# since Dolphin has no D-Bus method to query the current selection and a
# global Space bind would break typing everywhere.
#
# Toggle semantics: same file while a preview is open -> close it. Different
# file while a preview is open -> replace it. Nothing open -> launch fresh.
#
# Escape also closes the preview window directly, since Space is a Dolphin-
# side shortcut that only fires while Dolphin itself has focus -- pressing it
# with focus on the preview window does nothing. Each viewer gets Escape
# wired in via an instance-scoped override (env var / CLI flag) rather than
# its global config, so this doesn't change Escape's behavior for normal,
# non-quicklook use of imv/mpv/zathura/kitty. Images additionally close on
# Space (imv has nothing else to do with it); mpv keeps Space for pause.

FILE="$1"
STATE_FILE="/tmp/quicklook-state"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -z "$FILE" ]]; then
    exit 1
fi

if [[ -f "$STATE_FILE" ]]; then
    OLD_PID="$(cut -d: -f1 "$STATE_FILE")"
    OLD_FILE="$(cut -d: -f2- "$STATE_FILE")"

    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        rm -f "$STATE_FILE"

        if [[ "$OLD_FILE" == "$FILE" ]]; then
            exit 0
        fi
    fi
fi

case "${FILE,,}" in
    *.ts|*.tsx|*.go|*.rs|*.py|*.js|*.jsx|*.c|*.h|*.cpp|*.hpp|*.lua|*.sh|*.bash|*.zsh|*.toml|*.yaml|*.yml|*.json|*.md|*.conf|*.rc|*.txt|*.ini|*.xml|*.html|*.css)
        MIME="text/plain"
        ;;
    *)
        MIME="$(file --mime-type -b "$FILE" 2>/dev/null)"
        ;;
esac

case "$MIME" in
    image/*)
        # Load every image in the same folder (natural sort, like Dolphin)
        # and start on the selected one, so Left/Right flip through them.
        # Matched by extension rather than `file` per entry to stay fast in
        # big folders.
        mapfile -d '' IMAGES < <(find "$(dirname -- "$FILE")" -maxdepth 1 -type f \
            -regextype posix-extended -iregex '.*\.(jpe?g|png|gif|webp|bmp|tiff?|svg|heic|avif|jxl)' \
            -print0 | sort -zV)
        [[ ${#IMAGES[@]} -eq 0 ]] && IMAGES=("$FILE")
        setsid env imv_config="$SCRIPT_DIR/quicklook-imv.conf" \
            imv -i quicklook-preview -n "$FILE" -- "${IMAGES[@]}" >/dev/null 2>&1 &
        ;;
    application/pdf)
        setsid zathura --config-dir="$SCRIPT_DIR/quicklook-zathurarc" -- "$FILE" >/dev/null 2>&1 &
        ;;
    video/*)
        setsid mpv --wayland-app-id=quicklook-preview --autofit-larger=70%x70% --autofit-smaller=40%x40% \
            --input-conf="$SCRIPT_DIR/quicklook-mpv-input.conf" -- "$FILE" >/dev/null 2>&1 &
        ;;
    *)
        setsid kitty --class quicklook-preview --hold -o "map escape close_os_window" -e bash -c \
            'bat --paging=always -- "$1" || less -- "$1" || cat -- "$1"' _ "$FILE" >/dev/null 2>&1 &
        ;;
esac

echo "$!:$FILE" > "$STATE_FILE"
