#!/usr/bin/env bash
# Sets the wallpaper. Images go to awww; videos loop in mpvpaper over awww, which holds a
# poster of their first frame. Quickshell runs the transition into a video itself, over the
# already playing player (see modules/wallpaper/WallpaperTransition.qml).
# Usage:
#   wallpaper.sh set FILE [POSTER] [POS] [SECONDS]  switch to FILE, growing from POS (bottom, left,
#                                     right) for SECONDS; POSTER is where a video's first frame is kept
#   wallpaper.sh play VIDEO           start VIDEO unless one is already playing
#   wallpaper.sh freeze FRAME         pause the video that's on and save the frame it shows to FRAME
#   wallpaper.sh start VIDEO POSTER   replace the video that's on, starting from POSTER in awww
#   wallpaper.sh cue SECONDS          pause the video that's on at SECONDS
#   wallpaper.sh resume               play it on from there
#   wallpaper.sh poster VIDEO POSTER  write VIDEO's first frame to POSTER unless it's up to date
#   wallpaper.sh posters CACHE DIR    posters for every video under DIR, named by md5 of the path
#   wallpaper.sh mono CACHE DIR       negatives of every image under DIR, named by md5 of the path
#   wallpaper.sh gray IMAGE CACHE     black-and-white copy of IMAGE, named by md5 of the path
#   wallpaper.sh bw on|off [POSTER]   black-and-white mode for videos: the player desaturates and
#                                     awww holds the gray copy of POSTER
#   wallpaper.sh still VIDEO POSTER   make POSTER (and its gray copy in bw mode), print the one to show
#   wallpaper.sh grays CACHE DIR      list the images under DIR that are already black and white and
#                                     make black-and-white copies of the rest, so toggling is instant
set -u

run=${XDG_RUNTIME_DIR:-/tmp}/qs-wallpaper
sock=$run.sock

is_video() {
    case "${1,,}" in
    *.mp4 | *.webm | *.mkv | *.mov) return 0 ;;
    esac
    return 1
}

poster() {
    [ -s "$2" ] && [ "$2" -nt "$1" ] && return 0
    mkdir -p "${2%/*}"
    ffmpeg -nostdin -v error -y -i "$1" -frames:v 1 -q:v 2 "$2.tmp.jpg" && mv -f "$2.tmp.jpg" "$2"
}

# The gray copy of a poster sits next to it
gray_poster() {
    local out=${1%.jpg}-gray.jpg
    [ -s "$out" ] && [ "$out" -nt "$1" ] && return 0
    magick "$1" -colorspace Gray -colorspace sRGB -type TrueColor -quality 95 "$out.$$.jpg" && mv -f "$out.$$.jpg" "$out"
}

# The poster awww should hold: its gray copy in bw mode
shown() {
    if [ -f "$run.bw" ] && gray_poster "$1"; then
        printf '%s' "${1%.jpg}-gray.jpg"
    else
        printf '%s' "$1"
    fi
}

mono() {
    local out=$2/$(printf '%s' "$1" | md5sum | cut -c1-32)-neg.png
    [ -s "$out" ] && [ "$out" -nt "$1" ] && return 0
    mkdir -p "$2"
    magick "$1" -background black -flatten -alpha off -negate "$out.$$.png" && mv -f "$out.$$.png" "$out"
}

gray() {
    local out=$2/$(printf '%s' "$1" | md5sum | cut -c1-32)-gray.jpg
    [ -s "$out" ] && [ "$out" -nt "$1" ] && return 0
    mkdir -p "$2"
    magick "$1[0]" -background black -flatten -alpha off -colorspace Gray -colorspace sRGB -type TrueColor -quality 95 "$out.$$.jpg" && mv -f "$out.$$.jpg" "$out"
}

# Mean chroma of a small copy, cached next to the variants; under 0.04 counts as black and white
chroma() {
    local c=$2/$(printf '%s' "$1" | md5sum | cut -c1-32).chroma
    if ! { [ -s "$c" ] && [ "$c" -nt "$1" ]; }; then
        mkdir -p "$2"
        magick "$1[0]" -resize 64x64 -colorspace HCL -channel G -separate +channel -format '%[fx:mean]' info: >"$c" 2>/dev/null || return 1
    fi
    awk '{ exit !($1 < 0.04) }' "$c"
}

# A player that's gone can linger as a zombie for a while
playing() {
    pgrep -x -r D,R,S,T mpvpaper
}

grow() {
    if [ "${2:-}" = none ]; then
        awww img "$1" --transition-type none
        return
    fi
    awww img "$1" --transition-type grow --transition-pos "${2:-bottom}" \
        --transition-duration "${3:-0.8}" --transition-fps 60
}

play() {
    playing >/dev/null && return 0
    [ -f "$1" ] || return 1
    printf '%s' "$1" >"$run.video"
    # -p pauses it while nothing of the desktop is visible. mpv's default scaling of 4K videos
    # keeps an integrated GPU busy enough to drop frames; profile=fast takes a third of that
    local sat=0
    [ -f "$run.bw" ] && sat=-100
    setsid -f mpvpaper -p \
        -o "no-audio loop hwdec=auto-safe profile=fast panscan=1.0 saturation=$sat input-ipc-server=$sock" \
        ALL "$1" </dev/null >/dev/null 2>&1
}

mpv() {
    printf '%s\n' "$1" | socat -t 1 - "UNIX-CONNECT:$sock" 2>/dev/null
}

screenshot() {
    local i
    for i in $(seq 30); do
        mpv '{"command":["screenshot-to-file","'"$1"'","video"]}' | grep -q '"success"' && return 0
        sleep 0.03
    done
    return 1
}

# mpv can't screenshot frames that stay on the GPU, so it re-decodes the paused one with copy-back
# first (playing that way all along costs several times the CPU); ffmpeg is the fallback
freeze() {
    playing >/dev/null || return 1
    mpv '{"command":["set_property","pause",true]}' >/dev/null
    local t video
    t=$(mpv '{"command":["get_property","time-pos"]}' | sed -n 's/.*"data":\([0-9.]*\).*/\1/p')
    video=$(cat "$run.video" 2>/dev/null)
    mpv '{"command":["set_property","hwdec","auto-copy-safe"]}' >/dev/null
    screenshot "$1" || { [ -n "$t" ] && [ -f "$video" ] &&
        ffmpeg -nostdin -v error -y -ss "$t" -i "$video" -frames:v 1 -q:v 2 "$1"; }
}

kill_player() {
    pkill -x mpvpaper || return 0
    local i
    for i in $(seq 50); do
        playing >/dev/null || break
        sleep 0.02
    done
    rm -f "$sock" "$run.video"
}

# Leaves awww showing the frame the video is paused on, so the next transition starts from it
stop() {
    local frame=$run-frame.jpg
    if freeze "$frame"; then
        awww img "$frame" --transition-type none
        sleep 0.15
    fi
    kill_player
}

# Pauses the video that's on at SECONDS, ready for resume
cue() {
    mpv '{"command":["set_property","pause",true]}' >/dev/null
    mpv '{"command":["seek","'"$1"'","absolute+exact"]}' >/dev/null
    local i
    for i in $(seq 50); do
        mpv '{"command":["get_property","time-pos"]}' |
            sed -n 's/.*"data":\([0-9.]*\).*/\1/p' | awk -v t="$1" '$1 >= t - 0.05 { ok = 1 } END { exit !ok }' && return 0
        sleep 0.02
    done
    return 1
}

# Prints "poster" once awww holds it with the old player gone, then "ready" once the new one plays
start() {
    poster "$1" "$2" || exit 1
    [ -f "$run.pid" ] && kill "$(cat "$run.pid")" 2>/dev/null
    echo $$ >"$run.pid"
    awww img "$(shown "$2")" --transition-type none
    kill_player
    echo poster
    play "$1" || exit 1
    local i
    for i in $(seq 100); do
        mpv '{"command":["get_property","playback-time"]}' |
            sed -n 's/.*"data":\([0-9.]*\).*/\1/p' | awk '$1 > 0 { ok = 1 } END { exit !ok }' && break
        sleep 0.03
    done
    echo ready
    rm -f "$run.pid"
}

set_wallpaper() {
    # A newer switch takes over from one still in progress
    [ -f "$run.pid" ] && kill "$(cat "$run.pid")" 2>/dev/null
    echo $$ >"$run.pid"
    if is_video "$1"; then
        poster "$1" "$2" || exit 1
        stop
        grow "$(shown "$2")" "${3:-bottom}" "${4:-0.8}"
        sleep "${4:-0.8}"
        play "$1"
    elif [ "${3:-}" = none ]; then
        # Quickshell has grown it over the screen already: nothing to show under it on the way out
        grow "$1" none
        kill_player
    else
        stop
        grow "$1" "${3:-bottom}" "${4:-0.8}"
    fi
    rm -f "$run.pid"
}

case "${1:-}" in
set) set_wallpaper "$2" "${3:-}" "${4:-}" "${5:-}" ;;
play) play "$2" ;;
freeze) freeze "$2" ;;
start) start "$2" "$3" ;;
cue) cue "$2" ;;
resume) mpv '{"command":["set_property","pause",false]}' >/dev/null ;;
poster) poster "$2" "$3" ;;
still) poster "$2" "$3" && shown "$3" ;;
bw)
    if [ "$2" = on ]; then
        mkdir -p "${run%/*}" && : >"$run.bw"
        sat=-100
    else
        rm -f "$run.bw"
        sat=0
    fi
    if playing >/dev/null; then
        mpv '{"command":["set_property","saturation",'"$sat"']}' >/dev/null
        [ -n "${3:-}" ] && [ -f "$3" ] && awww img "$(shown "$3")" --transition-type none
    fi
    ;;
posters)
    find "$3" -type f | while IFS= read -r f; do
        if is_video "$f"; then
            p=$2/$(printf '%s' "$f" | md5sum | cut -c1-32).jpg
            poster "$f" "$p" && gray_poster "$p"
        fi
    done
    ;;
mono)
    find "$3" -type f | while IFS= read -r f; do
        is_video "$f" || mono "$f" "$2"
    done
    ;;
gray) gray "$2" "$3" ;;
grays)
    find "$3" -type f | while IFS= read -r f; do
        is_video "$f" && continue
        # Copies even for those, so nothing asks for a missing file before this list is read
        gray "$f" "$2"
        chroma "$f" "$2" && printf '%s\n' "$f"
    done
    ;;
*)
    sed -n '2,21s/^# \{0,1\}//p' "$0" >&2
    exit 1
    ;;
esac
