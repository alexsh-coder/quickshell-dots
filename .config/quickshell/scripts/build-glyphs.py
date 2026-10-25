#!/usr/bin/env python3
# Builds data/glyphs.json for the launcher's ":" mode from Unicode emoji-test.txt,
# CLDR annotations (en, ru) and Nerd Fonts glyphnames.json
import json, re, sys, urllib.request, xml.etree.ElementTree as ET
from pathlib import Path

CLDR = "https://raw.githubusercontent.com/unicode-org/cldr/main/common/"
OUT = Path(__file__).resolve().parent.parent / "data" / "glyphs.json"


def fetch(url):
    return urllib.request.urlopen(url, timeout=60).read()


def annotations(lang):
    names, words = {}, {}
    for kind in ("annotations", "annotationsDerived"):
        for a in ET.fromstring(fetch(f"{CLDR}{kind}/{lang}.xml")).iter("annotation"):
            cp = a.get("cp").replace("️", "")
            if a.get("type") == "tts":
                names[cp] = a.text
            else:
                words[cp] = a.text.replace(" | ", " ")
    return names, words


def main():
    en_names, en_words = annotations("en")
    ru_names, ru_words = annotations("ru")
    emoji = []
    for line in fetch("https://unicode.org/Public/emoji/latest/emoji-test.txt").decode().splitlines():
        m = re.match(r"^([0-9A-F ]+);\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$", line)
        # Skin tone variants would flood the list
        if not m or re.search(r"1F3F[B-F]", m.group(1)):
            continue
        char, name = m.group(2), m.group(3)
        key = char.replace("️", "")
        emoji.append([char, ru_names.get(key, name), " ".join(filter(None, [name, en_words.get(key), ru_words.get(key)])).lower()])
    nerd = [[v["code"], k] for k, v in json.loads(fetch("https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json")).items() if k != "METADATA"]
    OUT.write_text(json.dumps({"emoji": emoji, "nerd": nerd}, ensure_ascii=False, separators=(",", ":")))
    print(f"{len(emoji)} emoji, {len(nerd)} nerd glyphs -> {OUT}", file=sys.stderr)


main()
