#!/usr/bin/env python3
# Checks which Spotify Liked Songs have lyrics for the desktop lyrics:
# word-synced (karaoke glow), line-synced, plain text only, or none.
# Reads the library from the desktop client's local cache, no login needed.
# Usage: lyrics-scan.py [words|lines|text|none|error]   (no argument prints all)

import ctypes
import glob
import os
import struct
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lyrics  # noqa: E402

CACHE = os.path.expanduser("~/.cache/spotify/Users/*/primary.ldb")
LABELS = {"words": "по словам", "lines": "по строкам", "text": "только текст", "none": "нет текста",
          "error": "не удалось проверить"}


# Minimal LevelDB reader: Spotify keeps its library in one, snappy-compressed
class LevelDB:
    def __init__(self, path):
        self.snappy = ctypes.CDLL("libsnappy.so.1")
        items = []
        for p in sorted(glob.glob(os.path.join(path, "*.ldb"))):
            items += self.table(p)
        for p in sorted(glob.glob(os.path.join(path, "*.log"))):
            items += self.log(p)
        self.data = {}
        for key, seq, kind, value in sorted(items, key=lambda x: x[1]):
            if kind == 1:
                self.data[key] = value
            else:
                self.data.pop(key, None)

    def unsnappy(self, data):
        n = ctypes.c_size_t()
        self.snappy.snappy_uncompressed_length(data, len(data), ctypes.byref(n))
        out = ctypes.create_string_buffer(n.value)
        self.snappy.snappy_uncompress(data, len(data), out, ctypes.byref(n))
        return out.raw[:n.value]

    def block(self, f, offset, size):
        f.seek(offset)
        raw = f.read(size + 1)
        return self.unsnappy(raw[:size]) if raw[size] == 1 else raw[:size]

    @staticmethod
    def entries(b):
        restarts = struct.unpack("<I", b[-4:])[0]
        end = len(b) - 4 - 4 * restarts
        i, key = 0, b""
        while i < end:
            shared, i = varint(b, i)
            own, i = varint(b, i)
            size, i = varint(b, i)
            key = key[:shared] + b[i:i + own]
            i += own
            yield key, b[i:i + size]
            i += size

    def table(self, path):
        with open(path, "rb") as f:
            f.seek(-48, 2)
            footer = f.read(48)
            _, i = varint(footer, 0)
            _, i = varint(footer, i)
            offset, i = varint(footer, i)
            size, i = varint(footer, i)
            for _, handle in self.entries(self.block(f, offset, size)):
                o, j = varint(handle, 0)
                s, _ = varint(handle, j)
                for key, value in self.entries(self.block(f, o, s)):
                    seq = struct.unpack("<Q", key[-8:])[0]
                    yield key[:-8], seq >> 8, seq & 0xff, value

    @staticmethod
    def log(path):
        data = open(path, "rb").read()
        records, buf, i = [], b"", 0
        while i + 7 <= len(data):
            if i % 32768 > 32768 - 7:
                i = (i // 32768 + 1) * 32768
                continue
            size, kind = struct.unpack("<H", data[i + 4:i + 6])[0], data[i + 6]
            payload = data[i + 7:i + 7 + size]
            i += 7 + size
            if kind == 1:
                records.append(payload)
            elif kind == 2:
                buf = payload
            elif kind == 3:
                buf += payload
            elif kind == 4:
                records.append(buf + payload)
        for r in records:
            if len(r) < 12:
                continue
            seq, count = struct.unpack("<QI", r[:12])
            j = 12
            try:
                for n in range(count):
                    kind = r[j]
                    j += 1
                    size, j = varint(r, j)
                    key = r[j:j + size]
                    j += size
                    value = b""
                    if kind == 1:
                        size, j = varint(r, j)
                        value = r[j:j + size]
                        j += size
                    yield key, seq + n, kind, value
            except IndexError:
                pass


def varint(b, i):
    result = shift = 0
    while True:
        c = b[i]
        i += 1
        result |= (c & 0x7f) << shift
        shift += 7
        if c < 0x80:
            return result, i


# Track.duration is a sint32
def zigzag(n):
    return (n >> 1) ^ -(n & 1)


# Protobuf fields as {number: [values]}, without a schema
def proto(b):
    fields, i = {}, 0
    try:
        while i < len(b):
            tag, i = varint(b, i)
            num, wire = tag >> 3, tag & 7
            if wire == 0:
                v, i = varint(b, i)
            elif wire == 2:
                size, i = varint(b, i)
                v = b[i:i + size]
                i += size
            elif wire == 1:
                v, i = b[i:i + 8], i + 8
            elif wire == 5:
                v, i = b[i:i + 4], i + 4
            else:
                break
            fields.setdefault(num, []).append(v)
    except IndexError:
        pass
    return fields


def liked_songs(db):
    tracks = []
    for key, value in db.items():
        if not key.startswith(b"!col#col#$spotify:track:"):
            continue
        uri = key[10:-1]
        added = proto(value).get(2, [0])[0]
        info = proto(db.get(b"!col#col.trk#$" + uri + b"#", b""))
        if 2 not in info:
            continue
        # Duration lives in the cached spotify.metadata.Track, wrapped in an Any
        meta = proto(db.get(b"!xmeta#cache#\x01*#$" + uri + b"#", b""))
        wrapped = proto(meta.get(2, [b""])[0])
        track = proto(wrapped.get(2, [b""])[0])
        tracks.append({
            "uri": uri.decode(),
            "title": info[2][0].decode(),
            "album": info.get(4, [b""])[0].decode(),
            "artist": ", ".join(a.decode() for a in info.get(8, [])),
            "duration": zigzag(track.get(7, [0])[0]) / 1000,
            "added": added,
        })
    return sorted(tracks, key=lambda t: -t["added"])


def check(track):
    try:
        lines, plain = lyrics.fetch(track["artist"], track["title"], track["album"], track["duration"])
    except Exception:
        return "error"
    if any(line["words"] for line in lines):
        return "words"
    if lines:
        return "lines"
    return "text" if plain else "none"


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    if only and only not in LABELS:
        sys.exit(__doc__ or "usage: lyrics-scan.py [words|lines|text|none|error]")
    paths = glob.glob(CACHE)
    if not paths:
        sys.exit("Spotify cache not found: " + CACHE)
    tracks = liked_songs(LevelDB(paths[0]).data)
    print(f"Liked Songs: {len(tracks)}, checking...", file=sys.stderr)
    lyrics.RETRIES = 6
    with ThreadPoolExecutor(2) as pool:
        kinds = list(pool.map(check, tracks))
    for kind in LABELS:
        if only and kind != only:
            continue
        group = [t for t, k in zip(tracks, kinds) if k == kind]
        print(f"\n{LABELS[kind]} ({len(group)})")
        for t in group:
            print(f"  {t['artist']} — {t['title']}")


if __name__ == "__main__":
    main()
