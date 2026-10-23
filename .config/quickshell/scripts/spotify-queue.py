#!/usr/bin/env python3
# Reads Spotify's queue, or plays a track from it, through the player of its own page
# (the client is a web app; see spotify_cdp.py).
#   spotify-queue.py list        -> JSON {"context": ..., "current": N, "tracks": [{"uri", "title", "artists", "art"}]}
#   spotify-queue.py play N URI  -> plays the N-th track of that list, if it is still URI
#   spotify-queue.py library     -> JSON [{"uri", "name", "kind", "art"}], Liked Songs first
#   spotify-queue.py open URI    -> plays that playlist, album or artist

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

# Other platform APIs (LibraryAPI etc.), by name from the client's registry
API = """(name => {
    const r = window.__qsPlatformRegistry;
    for (const [k] of r._map ?? Object.values(r).find(v => v instanceof Map))
        if ((k.description ?? String(k)) === name)
            return r.resolve(k);
})"""

FIND_REGISTRY = """(() => {
    if (!window.__qsPlatformRegistry) {
        const el = document.querySelector("#main") ?? document.body.firstElementChild;
        const key = Object.keys(el).find(k => k.startsWith("__reactContainer"));
        const stack = [el[key]];
        while (stack.length && !window.__qsPlatformRegistry) {
            const f = stack.pop();
            const v = f.memoizedProps?.value;
            if (v?.getRegistry && v?.getCollectionPlatformAPI)
                window.__qsPlatformRegistry = v.getRegistry();
            if (f.sibling) stack.push(f.sibling);
            if (f.child) stack.push(f.child);
        }
    }
})()"""

# Liked Songs in order (when not shuffled) is listed whole, with hand-added tracks after the
# current one; anything else is the few played tracks, the current one and what is up next
TRACKS = f"""(async () => {{
    const q = {FIND}.getQueue();
    const s = window.__qsPlayer.getState();
    const ok = t => /^spotify:(track|episode|local):/.test(t?.uri ?? "");
    const queued = q.queued.filter(ok);
    if (s.context?.metadata?.format_list_type === "liked-songs" && !s.shuffle && ok(q.current)) {{
        {FIND_REGISTRY};
        const all = (await {API}("LibraryAPI").getTracks({{ offset: 0, limit: 5000 }})).items.filter(ok);
        const at = all.findIndex(t => t.uri === q.current.uri);
        if (at >= 0)
            return {{ current: at, list: [...all.slice(0, at + 1), ...queued, ...all.slice(at + 1)] }};
    }}
    const prev = s.previousItems.filter(ok);
    const now = ok(q.current) ? [q.current] : [];
    return {{ current: prev.length, list: [...prev, ...now, ...queued, ...q.nextUp.filter(ok)] }};
}})()"""

LIST = f"""(async () => {{
    const image = t => {{
        const imgs = t.album?.images ?? t.images ?? [];
        const url = (imgs.find(i => i.label === "standard") ?? imgs[0])?.url ?? "";
        return url.startsWith("spotify:image:") ? "https://i.scdn.co/image/" + url.slice(14) : url;
    }};
    const all = await {TRACKS};
    return {{
        context: window.__qsPlayer.getState().context?.metadata?.context_description ?? "",
        current: all.current,
        tracks: all.list.map(t => ({{
            uri: t.uri,
            title: t.name,
            artists: (t.artists ?? []).map(a => a.name).join(", "),
            art: image(t)
        }}))
    }};
}})()"""


LIBRARY = f"""(async () => {{
    {FIND_REGISTRY};
    const image = u => u?.startsWith("spotify:image:") ? "https://i.scdn.co/image/" + u.slice(14) : u ?? "";
    const r = await {API}("LibraryAPI").getContents({{ offset: 0, limit: 200 }});
    return [{{ uri: "spotify:collection:tracks", name: "Liked Songs", kind: "liked", art: "" }},
        ...r.items.filter(i => ["playlist", "album", "artist"].includes(i.type)).map(i => ({{
            uri: i.uri, name: i.name, kind: i.type, art: image((i.images ?? [])[0]?.url)
        }}))];
}})()"""


def main():
    try:
        page = Page()
        if sys.argv[1:2] == ["list"]:
            json.dump(page.eval(LIST), sys.stdout, ensure_ascii=False)
        elif sys.argv[1:2] == ["library"]:
            json.dump(page.eval(LIBRARY), sys.stdout, ensure_ascii=False)
        elif sys.argv[1:2] == ["open"] and len(sys.argv) == 3:
            page.eval(f"""(async () => {{
                await {FIND}.play({{ uri: {json.dumps(sys.argv[2])} }}, {{}}, {{}});
                return true;
            }})()""")
        elif sys.argv[1:2] == ["play"] and len(sys.argv) == 4:
            ok = page.eval(f"""(async () => {{
                const all = await {TRACKS};
                const i = {int(sys.argv[2])};
                const t = all.list[i];
                if (t?.uri !== {json.dumps(sys.argv[3])})
                    return false;
                // skipTo only reaches what is up next, so the context is restarted at the rest
                const q = window.__qsPlayer.getQueue();
                const next = i > all.current && [...q.queued, ...q.nextUp].find(u => u.uri === t.uri);
                if (next)
                    await window.__qsPlayer.skipTo(next);
                else if (i !== all.current) {{
                    const ctx = window.__qsPlayer.getState().context;
                    await window.__qsPlayer.play({{ uri: ctx.uri, url: ctx.url }}, {{}}, {{ skipTo: t.uid ? {{ uid: t.uid, uri: t.uri }} : {{ uri: t.uri }} }});
                }}
                return true;
            }})()""")
            sys.exit(0 if ok else 1)
        else:
            sys.exit(2)
    except (OSError, RuntimeError, StopIteration, ValueError):
        sys.exit(1)


if __name__ == "__main__":
    main()
