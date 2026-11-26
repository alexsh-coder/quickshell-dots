import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import qs.services

// Prefix modes of the launcher. Every item is
// { key, title, subtitle, hint, icon | glyph + glyphFont | appIcon, confirm?, run(alt) }
Item {
    id: root

    required property var launcher
    property string mode: ""
    property string text: ""

    // RU layout puts other characters on the same keys: Shift+2 is ", Shift+; is Ж, Shift+. is Ю, / is .
    readonly property var prefixes: ({
        ">": "run", "Ю": "run", "?": "web", ":": "glyph", "Ж": "glyph",
        "@": "window", "\"": "window", "/": "file", ".": "file", "!": "action"
    })
    readonly property var info: ({
        run: { icon: "terminal", placeholder: "Run a command" },
        web: { icon: "travel_explore", placeholder: "Search the web  ·  ?y youtube  ?w wiki  ?a archwiki  ?gh github" },
        glyph: { icon: "mood", placeholder: "Emoji and Nerd Font icons" },
        window: { icon: "select_window", placeholder: "Open windows" },
        file: { icon: "folder_open", placeholder: "Files in home  ·  Ctrl Enter opens the folder" },
        action: { icon: "bolt", placeholder: "System actions" }
    })

    readonly property var engines: [
        { bang: "", name: "Google", icon: "search", url: "https://www.google.com/search?q=%s" },
        { bang: "y", name: "YouTube", icon: "smart_display", url: "https://www.youtube.com/results?search_query=%s" },
        { bang: "w", name: "Wikipedia", icon: "menu_book", url: "https://%l.wikipedia.org/w/index.php?search=%s" },
        { bang: "a", name: "ArchWiki", icon: "deployed_code", url: "https://wiki.archlinux.org/index.php?search=%s" },
        { bang: "aur", name: "AUR", icon: "package_2", url: "https://aur.archlinux.org/packages?K=%s" },
        { bang: "p", name: "Arch packages", icon: "inventory_2", url: "https://archlinux.org/packages/?q=%s" },
        { bang: "gh", name: "GitHub", icon: "code", url: "https://github.com/search?q=%s" },
        { bang: "m", name: "Maps", icon: "map", url: "https://www.google.com/maps/search/%s" },
        { bang: "t", name: "Google Translate", icon: "translate", url: "https://translate.google.com/?sl=auto&text=%s" },
        { bang: "ddg", name: "DuckDuckGo", icon: "search", url: "https://duckduckgo.com/?q=%s" }
    ]

    property var glyphs: null
    // The glyph list is only read once ":" is first used
    property bool wantGlyphs: false
    property var fileHits: []
    property string armed: ""

    function parse(query) {
        const first = query.charAt(0);
        return prefixes[first] ? { mode: prefixes[first], text: query.slice(1) } : { mode: "", text: "" };
    }

    function prepare() {
        armed = "";
        if (mode === "window")
            Hyprland.refreshToplevels();
        if (mode === "glyph")
            wantGlyphs = true;
        if (mode === "file")
            fileTimer.restart();
    }
    onModeChanged: prepare()
    onTextChanged: {
        armed = "";
        if (mode === "file")
            fileTimer.restart();
    }

    function match(hay, q) {
        return q.split(/\s+/).every(w => hay.includes(w));
    }

    readonly property var items: {
        const q = text.trim().toLowerCase();
        switch (mode) {
        case "run": return runItems(text.trim());
        case "web": return webItems(text);
        case "glyph": return glyphItems(q);
        case "window": return windowItems(q);
        case "file": return fileHits;
        case "action": return actionItems(q);
        }
        return [];
    }

    // Detached through a login shell, so aliases of the user's environment don't matter but PATH does
    function runItems(cmd) {
        const out = [];
        if (cmd)
            out.push({ key: "run:" + cmd, icon: "play_arrow", title: cmd, subtitle: "Run  ·  Ctrl Enter in terminal", hint: "",
                run: alt => runCommand(cmd, alt) });
        for (const old of state.runs.filter(c => c !== cmd && c.toLowerCase().includes(cmd.toLowerCase())).slice(0, 20))
            out.push({ key: "run:" + old, icon: "history", title: old, subtitle: "From history", hint: "", run: alt => runCommand(old, alt) });
        return out;
    }

    function runCommand(cmd, inTerminal) {
        state.runs = [cmd].concat(state.runs.filter(c => c !== cmd)).slice(0, 50);
        if (inTerminal)
            Quickshell.execDetached([Theme.terminal, "--hold", "sh", "-c", cmd]);
        else
            Quickshell.execDetached(["sh", "-c", cmd]);
    }

    function webItems(raw) {
        // "?y lofi" picks YouTube: a bang is the first word when it names an engine
        const m = raw.match(/^(\S+)\s+(.*)$/);
        const bang = m && engines.some(e => e.bang && e.bang === m[1].toLowerCase()) ? m[1].toLowerCase() : "";
        const q = (bang ? m[2] : raw).trim();
        const lang = /[а-яё]/i.test(q) ? "ru" : "en";
        const list = bang ? [engines.find(e => e.bang === bang)].concat(engines.filter(e => e.bang !== bang)) : engines;
        return list.map(e => ({
            key: "web:" + e.name, icon: e.icon, title: q ? `${e.name}: ${q}` : e.name,
            subtitle: e.bang ? `?${e.bang}` : "Default", hint: "",
            run: () => Qt.openUrlExternally(e.url.replace("%l", lang).replace("%s", encodeURIComponent(q)))
        })).filter(() => q);
    }

    function glyphItems(q) {
        if (!glyphs)
            return [];
        const emoji = glyphs.emoji;
        const nerd = glyphs.nerd;
        const out = [];
        const recent = state.glyphs;
        if (!q) {
            for (const c of recent) {
                const e = emoji.find(x => x[0] === c);
                out.push(e ? emojiItem(e) : nerdItem(nerd.find(x => String.fromCodePoint(parseInt(x[0], 16)) === c) ?? [c.codePointAt(0).toString(16), "recent"]));
            }
            return out.concat(emoji.slice(0, 60).filter(e => !recent.includes(e[0])).map(emojiItem));
        }
        // Exact names first, then names starting with the query, then keyword hits
        const rank = e => e[1].toLowerCase() === q || e[2].startsWith(q + " ") ? 0 : e[1].toLowerCase().startsWith(q) ? 1 : 2;
        out.push(...emoji.filter(e => match(e[1].toLowerCase() + " " + e[2], q))
            .map((e, i) => ({ e, r: rank(e) * 10000 + i }))
            .sort((a, b) => a.r - b.r)
            .slice(0, 60)
            .map(x => emojiItem(x.e)));
        // "nf-md-home" style names; "md home" works too
        const words = q.replace(/^nf-/, "").split(/[\s\-_]+/).filter(w => w);
        for (const n of nerd) {
            if (out.length >= 120)
                break;
            if (words.every(w => n[1].includes(w)))
                out.push(nerdItem(n));
        }
        return out;
    }

    function emojiItem(e) {
        return { key: "g:" + e[0], glyph: e[0], glyphFont: "Noto Color Emoji", title: e[1], subtitle: e[2].split(" ").slice(0, 6).join(" "), hint: "",
            run: () => copyGlyph(e[0]) };
    }

    function nerdItem(n) {
        const c = String.fromCodePoint(parseInt(n[0], 16));
        return { key: "g:" + n[0], glyph: c, glyphFont: Theme.nerdFont, title: n[1], subtitle: "U+" + n[0].toUpperCase(), hint: "",
            run: () => copyGlyph(c) };
    }

    function copyGlyph(c) {
        state.glyphs = [c].concat(state.glyphs.filter(x => x !== c)).slice(0, 24);
        // Paste into the focused window once the launcher is gone
        Quickshell.execDetached(["sh", "-c", `wl-copy -- "$1"
            win=$(hyprctl activewindow -j)
            sleep 0.2
            case $(echo "$win" | jq -r .class) in
                kitty|foot|Alacritty|com.mitchellh.ghostty|org.wezfurlong.wezterm|org.kde.konsole) mods="CTRL SHIFT" ;;
                *) mods=CTRL ;;
            esac
            addr=$(echo "$win" | jq -r .address)
            hyprctl dispatch 'hl.dsp.send_shortcut({mods="'"$mods"'", key="code:55", window="address:'"$addr"'"})' >/dev/null 2>&1`, "sh", c]);
    }

    function windowItems(q) {
        return Hyprland.toplevels.values
            .filter(t => t.lastIpcObject?.mapped !== false)
            .map(t => {
                const cls = t.lastIpcObject?.class ?? "";
                const entry = DesktopEntries.heuristicLookup(cls);
                return {
                    key: "w:" + t.address,
                    appIcon: entry?.icon ?? cls,
                    title: t.title || cls,
                    subtitle: `${entry ? Names.name(entry) : cls}  ·  workspace ${t.workspace?.name ?? "?"}`,
                    hint: "",
                    run: () => Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${t.address.replace(/^0x/, "")}" })`)
                };
            })
            .filter(i => !q || match((i.title + " " + i.subtitle).toLowerCase(), q));
    }

    function ipc(...args) {
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call"].concat(args));
    }

    function actionItems(q) {
        const onOff = on => on ? "On" : "Off";
        const all = [
            { key: "a:lock", icon: "lock", title: "Lock", words: "lock блок заблок", run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
            { key: "a:suspend", icon: "bedtime", title: "Suspend", words: "suspend sleep сон спать", run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
            { key: "a:logout", icon: "logout", title: "Log out", words: "logout exit выход выйти", confirm: true, run: () => Hyprland.dispatch("hl.dsp.exit()") },
            { key: "a:reboot", icon: "restart_alt", title: "Reboot", words: "reboot restart перезагрузка ребут", confirm: true, run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
            { key: "a:poweroff", icon: "power_settings_new", title: "Shut down", words: "shutdown poweroff выключить", confirm: true, run: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
            { key: "a:vpn", icon: "vpn_key", title: "VPN", subtitle: onOff(Vpn.on), words: "vpn впн", run: () => Vpn.toggle() },
            { key: "a:night", icon: "nightlight", title: "Night light", subtitle: onOff(NightMode.enabled), words: "night light ночной свет", run: () => NightMode.toggle() },
            { key: "a:caffeine", icon: "coffee", title: "Caffeine", subtitle: onOff(Caffeine.enabled), words: "caffeine awake кофе не спать", run: () => Caffeine.toggle() },
            { key: "a:theme", icon: "contrast", title: Scheme.light ? "Dark theme" : "Light theme", words: "theme dark light тема темная светлая", run: () => Scheme.toggle() },
            { key: "a:wall-next", icon: "wallpaper", title: "Next wallpaper", words: "wallpaper next обои следующие", run: () => ipc("wallpaper", "next") },
            { key: "a:wall-random", icon: "shuffle", title: "Random wallpaper", words: "wallpaper random обои случайные", run: () => ipc("wallpaper", "random") },
            { key: "a:wall-pick", icon: "photo_library", title: "Wallpapers", words: "wallpaper picker обои выбрать", run: () => ipc("wallpaper", "open") },
            { key: "a:clipboard", icon: "content_paste", title: "Clipboard history", words: "clipboard буфер история", run: () => ipc("clipboard", "toggle") },
            { key: "a:settings", icon: "settings", title: "Settings", words: "settings настройки", run: () => ipc("settings", "open") },
            { key: "a:power", icon: "power", title: "Power menu", words: "power menu питание", run: () => ipc("powermenu", "toggle") }
        ];
        return all
            .filter(a => !q || match((a.title + " " + a.words).toLowerCase(), q))
            .map(a => Object.assign({ subtitle: "", hint: "" }, a, armed === a.key ? { subtitle: "Press Enter again to confirm", armed: true } : {}));
    }

    // Returns true when the launcher should close
    function activate(item, alt) {
        if (!item)
            return false;
        if (item.confirm && armed !== item.key) {
            armed = item.key;
            return false;
        }
        armed = "";
        item.run(alt);
        return true;
    }

    Timer {
        id: fileTimer
        interval: 120
        onTriggered: {
            const q = root.text.trim();
            if (!q) {
                root.fileHits = [];
                return;
            }
            files.running = false;
            files.query = q;
            files.running = true;
        }
    }

    Process {
        id: files
        property string query
        command: ["sh", "-c", 'fd -t d -i --max-results 12 -F -- "$1" "$HOME" | sed "s/^/d /"; fd -t f -i --max-results 40 -F -- "$1" "$HOME" | sed "s/^/f /"', "sh", query]
        stdout: StdioCollector {
            onStreamFinished: {
                if (files.query !== root.text.trim())
                    return;
                const home = Quickshell.env("HOME");
                root.fileHits = text.split("\n").filter(l => l)
                    .map(l => ({ dir: l[0] === "d", path: l.slice(2).replace(/\/$/, "") }))
                    // Shallow, short paths first: they're usually what's meant
                    .sort((a, b) => a.path.split("/").length - b.path.split("/").length || a.path.length - b.path.length)
                    .slice(0, 40)
                    .map(f => {
                        const name = f.path.split("/").pop();
                        const ext = f.dir ? "" : (name.match(/\.([^.]+)$/)?.[1] ?? "").toLowerCase();
                        return {
                            key: "f:" + f.path,
                            icon: f.dir ? "folder" : root.fileIcon(ext),
                            title: name,
                            subtitle: f.path.replace(home, "~"),
                            hint: "",
                            run: alt => Qt.openUrlExternally("file://" + (alt && !f.dir ? f.path.replace(/\/[^/]*$/, "") : f.path))
                        };
                    });
            }
        }
    }

    function fileIcon(ext) {
        if (/^(png|jpe?g|gif|webp|svg|bmp|avif|heic)$/.test(ext)) return "image";
        if (/^(mp4|mkv|webm|mov|avi)$/.test(ext)) return "movie";
        if (/^(mp3|flac|ogg|opus|wav|m4a)$/.test(ext)) return "music_note";
        if (/^(pdf|epub|djvu)$/.test(ext)) return "picture_as_pdf";
        if (/^(zip|tar|gz|xz|zst|7z|rar)$/.test(ext)) return "folder_zip";
        if (/^(qml|js|ts|py|lua|sh|c|cpp|h|rs|go|java|json|toml|ya?ml|conf|ini|css|html)$/.test(ext)) return "code";
        return "description";
    }

    FileView {
        id: glyphFile
        path: root.wantGlyphs ? Quickshell.shellPath("data/glyphs.json") : ""
        onLoaded: root.glyphs = JSON.parse(text())
    }

    FileView {
        path: Quickshell.statePath("launcher-modes.json")
        blockLoading: true
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: state
            property list<string> runs: []
            property list<string> glyphs: []
        }
    }
}
