#!/usr/bin/env python3
# Reads Spotify's queue, or plays a track from it, through the player of its own page
# (the client is a web app; see spotify_cdp.py).
#   spotify-queue.py list        -> JSON {"context": ..., "tracks": [{"uri", "title", "artists", "art"}]}
#   spotify-queue.py play N URI  -> plays the N-th upcoming track, if it is still URI

import json
import sys

from spotify_cdp import Page

# The player API object, found once per page in React's props and kept on window
FIND = """(() => {
    if (!window.__qsPlayer) {
        const el = document.querySelector("#main") ?? document.body.firstElementChild;
        const key = Object.keys(el).find(k => k.startsWith("__reactContainer"));
        const stack = [el[key]];
        while (stack.length && !window.__qsPlayer) {
            const f = stack.pop();
            const api = f.memoizedProps?.playerAPI ?? f.memoizedProps?.value?.playerAPI;
            if (api?.getQueue)
                window.__qsPlayer = api;
            if (f.sibling) stack.push(f.sibling);
            if (f.child) stack.push(f.child);
        }
    }
    return window.__qsPlayer;
})()"""

# Tracks added by hand come first, then the rest of the context; delimiters are dropped
UPCOMING = f"""(() => {{
    const q = {FIND}.getQueue();
    return [...q.queued, ...q.nextUp].filter(t => /^spotify:(track|episode|local):/.test(t.uri));
}})()"""

LIST = f"""(() => {{
    const image = t => {{
        const imgs = t.album?.images ?? t.images ?? [];
        const url = (imgs.find(i => i.label === "standard") ?? imgs[0])?.url ?? "";
        return url.startsWith("spotify:image:") ? "https://i.scdn.co/image/" + url.slice(14) : url;
    }};
    return {{
        context: window.__qsPlayer.getState().context?.metadata?.context_description ?? "",
        tracks: {UPCOMING}.map(t => ({{
            uri: t.uri,
            title: t.name,
            artists: (t.artists ?? []).map(a => a.name).join(", "),
            art: image(t)
        }}))
    }};
}})()"""


def main():
    try:
        page = Page()
        if sys.argv[1:2] == ["list"]:
            json.dump(page.eval(LIST), sys.stdout, ensure_ascii=False)
        elif sys.argv[1:2] == ["play"] and len(sys.argv) == 4:
            ok = page.eval(f"""(async () => {{
                const t = {UPCOMING}[{int(sys.argv[2])}];
                if (t?.uri !== {json.dumps(sys.argv[3])})
                    return false;
                await window.__qsPlayer.skipTo(t);
                return true;
            }})()""")
            sys.exit(0 if ok else 1)
        else:
            sys.exit(2)
    except (OSError, RuntimeError, StopIteration, ValueError):
        sys.exit(1)


if __name__ == "__main__":
    main()
