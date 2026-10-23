#!/usr/bin/env python3
# Reads and toggles the liked state of the track playing in Spotify, through the library API
# of its own page (see spotify_cdp.py).
# Prints "liked<TAB>title", "unliked<TAB>title" or "none" when the state changes;
# reads "toggle" lines on stdin.

import importlib.util
import os
import select
import sys
import time

from spotify_cdp import Page

spec = importlib.util.spec_from_file_location("queue", os.path.join(os.path.dirname(__file__), "spotify-queue.py"))
queue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(queue)

STATE = f"""(async () => {{
    {queue.FIND_REGISTRY};
    const item = {queue.FIND}.getState().item;
    if (!item?.uri?.startsWith("spotify:track:"))
        return null;
    const [liked] = await {queue.API}("LibraryAPI").contains(item.uri);
    return [liked ? "liked" : "unliked", item.name ?? "", item.uri];
}})()"""


def toggle_js(uri, like):
    return f"""(async () => {{
        {queue.FIND_REGISTRY};
        await {queue.API}("LibraryAPI").{"add" if like else "remove"}({{ uris: ["{uri}"] }});
    }})()"""


def main():
    page = None
    last = None
    state = None
    while True:
        try:
            if page is None:
                page = Page()
            state = page.eval(STATE)
        except Exception:
            page = None
            state = None
        line = "\t".join(state[:2]) if state else "none"
        if line != last:
            last = line
            print(line, flush=True)
        # Back off while Spotify isn't there
        ready, _, _ = select.select([sys.stdin], [], [], 1 if page else 5)
        if ready:
            cmd = sys.stdin.readline()
            if not cmd:
                return
            if cmd.strip() == "toggle" and page and state:
                try:
                    page.eval(toggle_js(state[2], state[0] != "liked"))
                except Exception:
                    page = None
                # Always answer a toggle, so a press that didn't take puts the heart back
                last = None
                time.sleep(0.3)


if __name__ == "__main__":
    main()
