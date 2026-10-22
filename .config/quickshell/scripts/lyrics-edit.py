#!/usr/bin/env python3
# Backend of the lyrics editor in the media popout.
#   lyrics-edit.py load ARTIST TITLE ALBUM DURATION
#     prints {"lines": [...], "source": path | null, "k": stretch, "origin": "local" | "online" | "plain" | "none"}
#     lines are lyrics.py's, with "time": null for lines that aren't synced yet
#   lyrics-edit.py save JSON
#     JSON is {"artist", "title", "duration", "source", "k", "lines"} with word times null where unmarked;
#     writes Enhanced LRC to ~/.local/share/lyrics (lines without any time are kept as plain text)

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lyrics  # noqa: E402

STAMP = re.compile(r"\[\d+:\d+(?:\.\d+)?\]")


# Keeps the file's order, so lines that aren't synced yet stay where they were typed
def read_local(path, k):
    with open(path, encoding="utf-8") as f:
        raw = f.read().splitlines()
    out = []
    for line in raw:
        if re.fullmatch(r"\[([a-z]+):(.*)\]", line.strip()):
            continue
        if STAMP.search(line):
            out += lyrics.scale(lyrics.parse_lrc(line)[0], k)
        elif line.strip():
            out.append({"time": None, "text": line.strip(), "words": None})
    return out


def load(artist, title, album, duration):
    source = lyrics.local_source(artist, title, duration)
    if source:
        path, _, _, k = source
        lines = read_local(path, k)
        if lines:
            return {"lines": lines, "source": path, "k": k, "origin": "local"}
    try:
        lines, plain = lyrics.fetch(artist, title, album, duration)
        origin = "online"
    except Exception:
        lines, plain, origin = [], "", "none"
    if not lines and plain:
        lines = [{"time": None, "text": l.strip(), "words": None} for l in plain.splitlines()]
        origin = "plain"
    lines = [l for l in lines if l["text"].strip()]
    return {"lines": lines, "source": source[0] if source else None, "k": source[3] if source else 1,
            "origin": origin if lines else "none"}


def save(data):
    artist, title, duration = data["artist"], data["title"], float(data["duration"])
    lines, path, k = data["lines"], data.get("source"), float(data.get("k") or 1)
    # Fixes go back into the file they came from, unstretched to its version
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            _, tags = lyrics.parse_lrc(f.read())
        artist = tags.get("ar", artist)
        title = tags.get("ti", title)
        duration = lyrics.seconds(tags.get("length", "")) or duration / k
    else:
        os.makedirs(lyrics.LOCAL, exist_ok=True)
        name = re.sub(r'[/\\:*?"<>|]', "_", f"{artist.split(',')[0].strip()} - {title}")
        path, k = os.path.join(lyrics.LOCAL, name + ".lrc"), 1

    def unk(t):
        return None if t is None else max(0.0, float(t)) / k

    # A redone fragment may end up a hair after the old word that follows it
    last = None
    for line in lines:
        line["time"] = unk(line.get("time"))
        for w in line.get("words") or []:
            w["time"] = unk(w.get("time"))
            if w["time"] is not None:
                if last is not None and w["time"] <= last:
                    w["time"] = last + 0.05
                last = w["time"]

    def words_of(line):
        ws = [w for w in line.get("words") or [] if w["text"].strip()]
        return ws if ws and all(w["time"] is not None for w in ws) else None

    starts = []
    for line in lines:
        ws = words_of(line)
        first = next((w["time"] for w in line.get("words") or [] if w["time"] is not None), None)
        w0 = (line.get("words") or [{"time": None}])[0]["time"]
        starts.append(ws[0]["time"] if ws else next((t for t in (w0, line["time"], first) if t is not None), None))

    out = [f"[ar:{artist}]", f"[ti:{title}]", f"[length:{lyrics.stamp(duration)}]", ""]
    for i, line in enumerate(lines):
        text = line["text"].strip()
        if not text:
            continue
        ws = words_of(line)
        if starts[i] is None:
            out.append(text)
        elif not ws:
            out.append(f"[{lyrics.stamp(starts[i])}]{text}")
        else:
            end_word = ws[-1]["time"]
            nxt = next((s for s in starts[i + 1:] if s is not None), duration)
            end = min(nxt, end_word + 1.2) if nxt > end_word else end_word + 1.2
            body = "".join(f"<{lyrics.stamp(w['time'])}>{w['text']}" for w in ws)
            out.append(f"[{lyrics.stamp(starts[i])}]{body.rstrip()} <{lyrics.stamp(end)}>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    return path


def main():
    if sys.argv[1] == "load":
        json.dump(load(sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5])), sys.stdout, ensure_ascii=False)
    elif sys.argv[1] == "save":
        print(save(json.loads(sys.argv[2])))


if __name__ == "__main__":
    main()
