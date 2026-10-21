#!/usr/bin/env bash
# Sets the wallpaper. Images go to awww; videos loop in mpvpaper over awww, which holds a
# poster of their first frame, so awww's transition hands over to the video without a jump.
# Usage:
#   wallpaper.sh set FILE [POSTER]    switch to FILE; POSTER is where a video's first frame is kept
#   wallpaper.sh play VIDEO           start VIDEO unless one is already playing
#   wallpaper.sh poster VIDEO POSTER  write VIDEO's first frame to POSTER unless it's up to date
#   wallpaper.sh posters CACHE DIR    posters for every video under DIR, named by md5 of the path
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

grow() {
    awww img "$1" --transition-type grow --transition-pos bottom \
        --transition-duration 0.8 --transition-fps 60
}

play() {
    pgrep -x mpvpaper >/dev/null && return 0
    [ -f "$1" ] || return 1
    printf '%s' "$1" >"$run.video"
    # -p pauses it while nothing of the desktop is visible. mpv's default scaling of 4K videos
    # keeps an integrated GPU busy enough to drop frames; profile=fast takes a third of that
    setsid -f mpvpaper -p \
        -o "no-audio loop hwdec=auto-safe profile=fast panscan=1.0 input-ipc-server=$sock" \
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

# Leaves awww showing the frame the video is paused on, so the next transition starts from it.
# mpv can't screenshot frames that stay on the GPU, so it re-decodes the paused one with copy-back
# first (playing that way all along costs several times the CPU); ffmpeg is the fallback
stop() {
    pgrep -x mpvpaper >/dev/null || return 0
    mpv '{"command":["set_property","pause",true]}' >/dev/null
    local t video frame=$run-frame.jpg
    t=$(mpv '{"command":["get_property","time-pos"]}' | sed -n 's/.*"data":\([0-9.]*\).*/\1/p')
    video=$(cat "$run.video" 2>/dev/null)
    mpv '{"command":["set_property","hwdec","auto-copy-safe"]}' >/dev/null
    if screenshot "$frame" || { [ -n "$t" ] && [ -f "$video" ] &&
        ffmpeg -nostdin -v error -y -ss "$t" -i "$video" -frames:v 1 -q:v 2 "$frame"; }; then
        awww img "$frame" --transition-type none
        sleep 0.15
    fi
    pkill -x mpvpaper
    rm -f "$sock" "$run.video"
}

set_wallpaper() {
    # A newer switch takes over from one still in progress
    [ -f "$run.pid" ] && kill "$(cat "$run.pid")" 2>/dev/null
    echo $$ >"$run.pid"
    if is_video "$1"; then
        poster "$1" "$2" || exit 1
        stop
        grow "$2"
        sleep 0.8
        play "$1"
    else
        stop
        grow "$1"
    fi
    rm -f "$run.pid"
}

case "${1:-}" in
set) set_wallpaper "$2" "${3:-}" ;;
play) play "$2" ;;
poster) poster "$2" "$3" ;;
posters)
    find "$3" -type f | while IFS= read -r f; do
        is_video "$f" && poster "$f" "$2/$(printf '%s' "$f" | md5sum | cut -c1-32).jpg"
    done
    ;;
*)
    sed -n '2,9s/^# \{0,1\}//p' "$0" >&2
    exit 1
    ;;
esac
