#!/usr/bin/env python3
# Tap along to the playing track to make word-synced lyrics by hand.
# Space marks the start of the highlighted word; the result is saved as Enhanced
# LRC to ~/.local/share/lyrics, where lyrics.py picks it up (slowed and sped up
# versions of the same track reuse it, stretched).
# When the track already has a file, its timing is loaded and only the words
# you tap again are replaced, so a fragment can be redone: seek to it and tap.
#
#   space        mark the highlighted word     backspace  undo the last mark
#   left/right   seek 5 s, jump to that word   r          restart the track
#   [ ]          shift this session's marks    q          save and quit
#   ctrl+c       quit without saving

import curses
import os
import re
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lyrics  # noqa: E402


def playerctl(*args, player=None):
    cmd = ["playerctl", "-p", player or PLAYER] if (player or PLAYER) else ["playerctl"]
    return subprocess.run([*cmd, *args], capture_output=True, text=True).stdout.strip()


# The playing player, like the desktop lyrics; bare playerctl picks the first one listed
def pick_player():
    players = playerctl("-l").split()
    return next((p for p in players if playerctl("status", player=p) == "Playing"), players[0] if players else None)


PLAYER = None


class Clock(threading.Thread):
    """Player position, interpolated between polls so taps aren't delayed by playerctl."""

    def __init__(self):
        super().__init__(daemon=True)
        self.pos, self.at, self._playing = 0.0, time.monotonic(), False
        self.lock = threading.Lock()
        self.sync()

    def sync(self):
        pos = playerctl("position")
        playing = playerctl("status") == "Playing"
        with self.lock:
            self.pos = float(pos or 0)
            self.at = time.monotonic()
            self._playing = playing

    def run(self):
        while True:
            time.sleep(0.5)
            self.sync()

    @property
    def playing(self):
        with self.lock:
            return self._playing

    def now(self):
        with self.lock:
            return self.pos + (time.monotonic() - self.at if self._playing else 0)


def load_track():
    sep = "\x1f"
    meta = playerctl("metadata", "--format", sep.join(["{{artist}}", "{{title}}", "{{album}}", "{{mpris:length}}"]))
    if not meta:
        sys.exit("Nothing is playing")
    artist, title, album, length = meta.split(sep)
    duration = int(length or 0) / 1e6
    source = lyrics.local_source(artist, title, duration)
    if source:
        lines = lyrics.scale(source[2], source[3])
    else:
        lines, _ = lyrics.fetch(artist, title, album, duration)
    lines = [l for l in lines if l["text"].strip()]
    if not lines:
        sys.exit(f"No lyrics found for {artist} - {title}")
    return artist, title, duration, lines, source


def save(artist, title, duration, lines, words, times, source):
    # Fixes go back into the file they came from, unstretched to its version
    if source:
        path, tags, _, k = source
        artist, title, duration = tags.get("ar", artist), tags["ti"], lyrics.seconds(tags.get("length", "")) or duration / k
    else:
        os.makedirs(lyrics.LOCAL, exist_ok=True)
        name = re.sub(r'[/\\:*?"<>|]', "_", f"{artist.split(',')[0].strip()} - {title}")
        path, k = os.path.join(lyrics.LOCAL, name + ".lrc"), 1
    times = [None if t is None else max(0, t) / k for t in times]
    # A redone fragment may end up a hair after the old word that follows it
    for i in range(1, len(times)):
        if times[i] is not None and times[i - 1] is not None and times[i] <= times[i - 1]:
            times[i] = times[i - 1] + 0.05
    out = [f"[ar:{artist}]", f"[ti:{title}]", f"[length:{lyrics.stamp(duration)}]", ""]
    timed = []
    for li in range(len(lines)):
        idx = [i for i, (l, _) in enumerate(words) if l == li]
        timed.append(idx if idx and all(times[i] is not None for i in idx) else None)
    starts = [times[idx[0]] if idx else line["time"] / k for idx, line in zip(timed, lines)]
    for li, line in enumerate(lines):
        idx = timed[li]
        if not idx:
            out.append(f"[{lyrics.stamp(starts[li])}]{line['text']}")
            continue
        last = times[idx[-1]]
        nxt = starts[li + 1] if li + 1 < len(lines) else duration
        end = min(nxt, last + 1.2) if nxt > last else last + 1.2
        body = "".join(f"<{lyrics.stamp(times[i])}>{words[i][1]}" for i in idx)
        out.append(f"[{lyrics.stamp(starts[li])}]{body.rstrip()} <{lyrics.stamp(end)}>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    subprocess.run(["qs", "ipc", "call", "lyrics", "reload"], capture_output=True)
    return path


def ui(scr, artist, title, duration, lines, source):
    curses.curs_set(0)
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_CYAN, -1)
    curses.init_pair(2, 8 if curses.COLORS > 8 else curses.COLOR_WHITE, -1)
    scr.timeout(30)

    words, times = [], []
    for li, line in enumerate(lines):
        for w in line["words"] or [{"text": t, "time": None} for t in re.findall(r"\S+\s*", line["text"])]:
            if w["text"].strip():
                words.append((li, w["text"]))
                times.append(w["time"])
    edited, history, offset = set(), [], 0.0
    clock = Clock()
    clock.start()

    # The first word that isn't marked before the playhead: where tapping resumes
    def resume(pos):
        return next((i for i, t in enumerate(times) if t is None or t > pos), len(words))

    cursor = resume(clock.now() - 0.3)

    def seek(arg):
        nonlocal cursor
        playerctl("position", arg)
        time.sleep(0.05)
        clock.sync()
        cursor = resume(clock.now() - 0.3)

    while True:
        now = clock.now()
        key = scr.getch()
        # Taps while paused would all land on the same moment
        if key == ord(" ") and cursor < len(words) and clock.playing:
            history.append((cursor, times[cursor], cursor in edited))
            times[cursor] = now + offset
            edited.add(cursor)
            cursor += 1
        elif key in (curses.KEY_BACKSPACE, 127, 8) and history:
            cursor, times[cursor], was = history.pop()
            if not was:
                edited.discard(cursor)
        elif key == curses.KEY_LEFT:
            seek("5-")
        elif key == curses.KEY_RIGHT:
            seek("5+")
        elif key == ord("r"):
            seek("0")
        elif key in (ord("["), ord("]")):
            step = -0.01 if key == ord("[") else 0.01
            offset += step
            for i in edited:
                times[i] += step
        elif key == ord("q"):
            return save(artist, title, duration, lines, words, times, source) if edited else None

        cur = words[cursor][0] if cursor < len(words) else len(lines)
        scr.erase()
        h, w = scr.getmaxyx()
        scr.addnstr(0, 0, f"{artist} — {title}", w - 1, curses.A_BOLD)
        status = (f"{lyrics.stamp(now)} / {lyrics.stamp(duration)}   "
                  f"{sum(t is not None for t in times)}/{len(words)} marked, {len(edited)} redone   "
                  f"offset {offset * 1000:+.0f} ms")
        scr.addnstr(1, 0, status, w - 1, curses.color_pair(2))
        scr.addnstr(2, 0, "space mark · backspace undo · ←/→ seek 5s · r restart · [ ] offset · q save", w - 1,
                    curses.color_pair(2))
        for row, li in enumerate(range(cur - 2, cur + 6)):
            y = 4 + row
            if y >= h - 1 or li < 0 or li >= len(lines):
                continue
            x = 2
            for wi, (l, word) in enumerate(words):
                if l != li or x >= w - 1:
                    continue
                if wi == cursor:
                    attr = curses.A_REVERSE | curses.A_BOLD
                elif wi in edited:
                    attr = curses.color_pair(1) | curses.A_BOLD
                elif times[wi] is not None:
                    attr = curses.color_pair(1) | curses.A_DIM
                else:
                    attr = curses.A_BOLD if li == cur else curses.color_pair(2)
                scr.addnstr(y, x, word, w - 1 - x, attr)
                x += len(word)
        scr.refresh()


def main():
    global PLAYER
    PLAYER = pick_player()
    track = load_track()
    try:
        path = curses.wrapper(ui, *track)
    except KeyboardInterrupt:
        print("Quit without saving")
        return
    print(f"Saved {path}" if path else "Nothing marked, nothing saved")


if __name__ == "__main__":
    main()
