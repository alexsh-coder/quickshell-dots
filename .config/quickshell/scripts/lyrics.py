#!/usr/bin/env python3
# Fetches synced lyrics for a track and prints them as JSON:
# [{"time": s, "text": str, "words": [{"time": s, "dur": s, "text": str}] | null}]
# Sources in order: hand-made Enhanced LRC files in ~/.local/share/lyrics
# (see lyrics-tap.py), Kugou's KRC for word timing, lrclib.net for lines.
# Usage: lyrics.py ARTIST TITLE ALBUM DURATION_SECONDS

import base64
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor

LOCAL = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "lyrics")
KRC_KEY = b"@Gaw^2tGQ61-\xce\xd2ni"
# Kugou prepends credits ("Lyrics by：...") and copyright notes
JUNK = re.compile(r"^[^:：]{1,40}[:：]|未经|著作权|TME")


# Retries on timeouts and rate limits (lrclib answers 429/503 under load)
RETRIES = 3


def get(url, params):
    req = urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(RETRIES):
        wait = 2 ** attempt
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404 or attempt == RETRIES - 1:
                raise
            retry_after = e.headers.get("Retry-After", "")
            wait = int(retry_after) if retry_after.isdigit() else wait
        except (urllib.error.URLError, TimeoutError):
            if attempt == RETRIES - 1:
                raise
        time.sleep(wait)


def norm(s):
    s = re.sub(r"\s+-\s+.*$|\s*[(\[].*?[)\]]", "", s.lower())
    return re.sub(r"\W+", "", s)


def grams(text):
    t = re.sub(r"\W+", "", text.lower())
    return {t[i:i + 2] for i in range(len(t) - 1)}


def similarity(a, b):
    a, b = grams(a), grams(b)
    return len(a & b) / max(1, min(len(a), len(b)))


def kugou_search(artist, title, duration):
    artist = artist.split(",")[0].strip()
    found = get("https://lyrics.kugou.com/search", {
        "ver": 1, "man": "yes", "client": "pc",
        "keyword": f"{artist} - {re.sub(r' - .*$', '', title)}",
        "duration": int(duration * 1000), "hash": "",
    })
    return [c for c in found.get("candidates", [])
            if abs(c["duration"] / 1000 - duration) <= 3 and norm(c["song"]) == norm(title)][:6]


def kugou_download(c):
    try:
        d = get("https://lyrics.kugou.com/download", {
            "ver": 1, "client": "pc", "fmt": "krc", "charset": "utf8",
            "id": c["id"], "accesskey": c["accesskey"],
        })
        raw = base64.b64decode(d["content"])[4:]
        return parse_krc(zlib.decompress(bytes(b ^ KRC_KEY[i % 16] for i, b in enumerate(raw))).decode())
    except Exception:
        return []


# Kugou lists transliterations and translations next to the original,
# so candidates are checked against the lrclib text when there is one
def kugou_pick(results, reference):
    results = [r for r in results if r]
    if not reference:
        return results[0] if results else None
    best, score = None, 0.4
    for lines in results:
        sim = similarity(reference, " ".join(l["text"] for l in lines))
        if sim > score:
            best, score = lines, sim
    return best


def parse_krc(krc):
    out = []
    for m in re.finditer(r"^\[(\d+),(\d+)\](.*)$", krc, re.M):
        start = int(m[1]) / 1000
        words = [{"time": round(start + int(w[1]) / 1000, 3), "dur": int(w[2]) / 1000, "text": w[3].replace("\r", "")}
                 for w in re.finditer(r"<(\d+),(\d+),\d+>([^<]*)", m[3])]
        text = "".join(w["text"] for w in words).strip()
        if not text:
            continue
        if not out and (JUNK.search(text) or " - " in text):
            continue
        out.append({"time": start, "text": text, "words": words})
    return out


def stamp(t):
    return f"{int(t // 60):02d}:{t % 60:05.2f}"


def seconds(stamp):
    m = re.fullmatch(r"\s*(\d+):(\d+(?:\.\d+)?)\s*", stamp)
    return int(m[1]) * 60 + float(m[2]) if m else 0


# LRC with optional Enhanced LRC word stamps: [01:02.30]<01:02.30>word <01:02.80>word<01:03.40>
def parse_lrc(text):
    tags, out = {}, []
    for raw in text.splitlines():
        tag = re.fullmatch(r"\[([a-z]+):(.*)\]", raw.strip())
        if tag:
            tags[tag[1]] = tag[2].strip()
            continue
        body = re.sub(r"\[[^\]]*\]", "", raw)
        marks = [(seconds(m[1]), m[2]) for m in re.finditer(r"<([\d:.]+)>([^<]*)", body)]
        words = None
        if marks:
            words = [{"time": t, "dur": round((marks[i + 1][0] if i + 1 < len(marks) else t + 1) - t, 3), "text": w}
                     for i, (t, w) in enumerate(marks) if w.strip()]
        text_ = "".join(w["text"] for w in words).strip() if words else body.strip()
        for m in re.finditer(r"\[(\d+:\d+(?:\.\d+)?)\]", raw):
            out.append({"time": seconds(m[1]), "text": text_, "words": words})
    return sorted(out, key=lambda l: l["time"]), tags


def scale(lines, k):
    return [{"time": l["time"] * k, "text": l["text"],
             "words": [{"time": w["time"] * k, "dur": w["dur"] * k, "text": w["text"]} for w in l["words"]]
             if l["words"] else None} for l in lines]


# True for "Song" or "Song - Slowed + Reverb", false for "Song - Remix"
def stretch_of(title):
    m = re.search(r"\s+-\s+(.*)$|\s*[(\[](.*?)[)\]]", title)
    if not m:
        return True
    extra = re.sub(r"slow(ed)?|sped|speed|up|nightcore|daycore|reverb|super|ultra|[\W_x]+", "", (m[1] or m[2]).lower())
    return not extra


# Hand-made lyrics, matched by their [ar:] and [ti:] tags. A slowed or sped up
# version reuses the timing of another one, stretched by the duration ratio.
# Returns (path, tags, lines, k): k is the stretch from the file to this track
def local_source(artist, title, duration):
    stretched = None
    for path in glob.glob(os.path.join(LOCAL, "*.lrc")):
        with open(path, encoding="utf-8") as f:
            lines, tags = parse_lrc(f.read())
        if norm(tags.get("ar", "").split(",")[0]) != norm(artist.split(",")[0]) or norm(tags.get("ti", "")) != norm(title):
            continue
        if tags["ti"].strip().lower() == title.strip().lower():
            return path, tags, lines, 1
        length = seconds(tags.get("length", ""))
        if length and duration and stretch_of(tags["ti"]) and stretch_of(title):
            stretched = path, tags, lines, duration / length
    return stretched


def local(artist, title, duration):
    found = local_source(artist, title, duration)
    if not found:
        return None
    _, _, lines, k = found
    return lines if k == 1 else scale(lines, k)


def lrclib(artist, title, album, duration):
    base = "https://lrclib.net/api"
    # A joined "A, B" artist makes /get miss and stall
    artist = artist.split(",")[0].strip()
    try:
        items = [get(base + "/get", {"artist_name": artist, "track_name": title,
                                     "album_name": album, "duration": round(duration)})]
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        items = get(base + "/search", {"artist_name": artist, "track_name": title})
    plain = next((i["plainLyrics"] for i in items if i.get("plainLyrics")), "")
    items = [i for i in items if i.get("syncedLyrics")]
    if not items:
        return [], False, plain
    items.sort(key=lambda i: abs((i.get("duration") or 0) - duration))
    exact = abs((items[0].get("duration") or 0) - duration) <= 3
    return parse_lrc(items[0]["syncedLyrics"])[0], exact, plain


# Returns (lines, plain): plain is lrclib's unsynced text, if it has any.
# Raises when nothing was found and a source failed, so a miss isn't mistaken for "no lyrics"
def fetch(artist, title, album, duration):
    mine = local(artist, title, duration)
    if mine:
        return mine, True
    error = None
    with ThreadPoolExecutor(8) as pool:
        synced = pool.submit(lrclib, artist, title, album, duration)
        try:
            krc = list(pool.map(kugou_download, kugou_search(artist, title, duration)))
        except Exception as e:
            krc, error = [], e
        try:
            synced, exact, plain = synced.result()
        except Exception as e:
            synced, exact, plain, error = [], False, "", e
    reference = " ".join(l["text"] for l in synced) if exact else ""
    lines = kugou_pick(krc, reference) or synced
    if not lines and not plain and error:
        raise error
    return lines, plain


def main():
    try:
        lines, _ = fetch(sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]))
    except Exception:
        sys.exit(1)
    if lines and lines[0]["time"] > 0:
        lines.insert(0, {"time": 0, "text": "", "words": None})
    json.dump(lines, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
