pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cursor theme (installed ones grouped into families, optionally recolored to the accent, applied
// live) and the pointer position for the cursor effects
Singleton {
    id: root

    // [{ name, path, family, style, color }], from the icon dirs
    property var themes: []
    // Family names in order, and the themes of the one picked
    readonly property var families: [...new Set(themes.map(t => t.family))]
    readonly property var current: themes.find(t => t.name === base) ?? null
    readonly property var siblings: themes.filter(t => t.family === current?.family)

    // What was picked, and what Hyprland runs (Tinted-<base> when recolored)
    readonly property string base: Settings.cursorBase || Quickshell.env("XCURSOR_THEME") || "default"
    readonly property bool selfColored: base.startsWith("Rice-")
    // Recolor needs XCursor files; the anime ones' hand-drawn art is left alone
    readonly property bool recolorable: !!current && current.xcursor && !selfColored && current.family !== "Anime"
    // "black", "white" or "accent" for recolorable themes, else ""
    readonly property string tint: recolorable ? Settings.cursorColor : ""
    // XCursor themes run from a rebuilt copy: every size, and the common names some lack
    readonly property bool fix: !!current?.xcursor && !tint && !selfColored
    readonly property var tints: ({ black: "#1c1c1c", white: "#f5f5f5" })
    // Rice ones draw themselves in the accent; a copy per color all the same, as Hyprland
    // won't reload a theme under a name it has loaded
    readonly property bool followsAccent: tint === "accent" || selfColored
    readonly property string tintHex: tint || selfColored ? String(tints[tint] ?? Accent.cursorTarget).slice(1).toLowerCase() : ""
    readonly property string theme: tintHex ? "Tinted-" + tintHex + "-" + base : fix ? "Fixed-" + base : base
    readonly property int size: Settings.get("cursor_size")

    // Pointer in Hyprland layout coords, while some effect wants it
    readonly property bool tracking: Settings.cursorTrail !== "off" || Settings.cursorViz && Cava.active
    property real x: 0
    property real y: 0
    // Where the pointer will be a frame from now: effects render a frame behind Hyprland
    property real vx: 0
    property real vy: 0
    property real stamp: 0
    readonly property real ahead: Settings.vizLead
    readonly property real px: x + vx * ahead
    readonly property real py: y + vy * ahead
    // No movement for Settings.cursorIdle seconds
    property bool idle: false

    // Picks a family, style or color, keeping the rest where the family has it
    function pick(family, style, color) {
        const t = themeFor(family, style, color);
        if (t)
            Settings.cursorBase = t.name;
    }
    // The theme pick() would land on
    function themeFor(family, style, color) {
        if (current?.family === family && (!style || current.style === style) && (!color || current.color === color))
            return current;
        const list = themes.filter(t => t.family === family);
        // Rice opens on Fluent unless a style is asked for
        if (family === "Rice" && !list.some(t => t.style === style))
            style = "Fluent";
        // A neutral variant makes the cleanest base for recoloring
        const plain = ["Classic", "Dark", "Black", "White", "Light", ""];
        const byColor = l => (color && l.find(t => t.color === color)) || plain.map(c => l.find(t => t.color === c)).find(t => t) || l[0];
        const same = list.filter(t => t.style === style);
        return byColor(same.length ? same : list) ?? list[0];
    }

    function classify(name) {
        const rules = [
            [/^Bibata-(Modern|Original)-(\w+?)$/, m => ["Bibata", m[1], m[2]]],
            [/^ComixCursors-(Slim-)?(\w+)$/, m => ["Comix", m[1] ? "Slim" : "Regular", m[2]]],
            // [/^Oxygen_(\w+)$/, m => ["Oxygen", "", m[1]]],
            [/^capitaine-cursors(-light)?$/, m => ["Capitaine", "", m[1] ? "Light" : "Dark"]],
            [/^Vimix-(white-)?cursors$/, m => ["Vimix", "", m[1] ? "White" : "Dark"]],
            [/^(breeze_cursors|Breeze_Light)$/, m => ["Breeze", "", m[1] === "Breeze_Light" ? "Light" : "Dark"]],
            [/^Rice-(\w+)$/, m => ["Rice", m[1], ""]],
            [/^miku-cursor/, m => ["Anime", "Miku", ""]],
            [/^(Koishi|nahida|furina|bocchi|nijika)$/, m => ["Anime", m[1].charAt(0).toUpperCase() + m[1].slice(1), ""]],
        ];
        for (const [re, f] of rules) {
            const m = name.match(re);
            if (m)
                return f(m);
        }
        return [name.replace(/[-_]+/g, " ").replace(/\bcursors?\b/i, "").trim(), "", ""];
    }

    // Hyprland only redraws a client's cursor when the client sets a shape again
    signal applied

    // Lines from cursor-recolor.py: a copy built ("name") or evicted ("-name")
    // A complete copy is true, one with only some sizes their list ("48 56 64 96")
    function note(line) {
        const all = Object.assign({}, built);
        const [name, ...sizes] = line.trim().split(" ");
        if (name.startsWith("-"))
            delete all[name.slice(1)];
        else if (name)
            all[name] = sizes.length && all[name] !== true ? sizes.join(" ") : true;
        built = all;
    }
    function ready(name) {
        const b = built[name];
        return b === true || typeof b === "string" && steps.every(x => b.split(" ").includes(String(x)));
    }

    // Monitor scales: Hyprland loads the theme at size times each one, rounded up
    property var scales: [1]
    Process {
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.scales = JSON.parse(text).map(m => m.scale);
                } catch (e) {}
            }
        }
    }
    // Sizes a quick build makes (ONLY_SIZE of cursor-recolor.py), and the steps it turns them into
    readonly property string only: [size].concat(scales.map(k => Math.round(size * k)), scales.map(k => size * Math.ceil(k))).join(",")
    readonly property var steps: {
        const all = [20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 96];
        const out = new Set();
        for (const v of only.split(",").map(Number)) {
            out.add(all.find(x => x >= v) ?? all[all.length - 1]);
            out.add([...all].reverse().find(x => x <= v) ?? all[0]);
        }
        return [...out];
    }

    Process {
        id: setcursor
        stderr: SplitParser {
            onRead: line => console.warn("Cursor:", line)
        }
        onExited: code => {
            if (code === 0 && root.theme !== root.base) {
                shownStrip.command = [Quickshell.shellDir + "/scripts/cursor-preview.py", root.previewDir, Quickshell.env("HOME") + "/.local/share/icons/" + root.theme];
                shownStrip.running = true;
            }
            if (code === 3) {
                // A copy thought built is gone: build it again
                root.note("-" + root.theme);
                root.update();
                return;
            }
            root.applied();
            root.kicking = true;
        }
    }
    // Warping the pointer in place makes Hyprland re-pick the surface under it: once onto the
    // kick layer, once back, and the window there sets its shape again
    property bool kicking: false
    function nudge() {
        Quickshell.execDetached(["sh", "-c", "IFS=', ' read -r x y <<EOF\n$(hyprctl cursorpos)\nEOF\nhyprctl dispatch \"hl.dsp.cursor.move({x=$x,y=$y})\" >/dev/null"]);
    }
    Timer {
        running: root.kicking
        interval: 30
        onTriggered: {
            root.nudge();
            back.start();
        }
    }
    Timer {
        id: back
        interval: 30
        onTriggered: {
            root.kicking = false;
            done.start();
        }
    }
    Timer {
        id: done
        interval: 30
        onTriggered: root.nudge()
    }

    function apply() {
        hideIdle();
        console.info("Cursor: applying", theme, size);
        setcursor.command = ["sh", "-c", `for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
                [ -d "$d/$0/cursors" ] && exec hyprctl setcursor "$0" "$1" >/dev/null; done
            echo "theme $0 not found" >&2; exit 3`, theme, String(size)];
        setcursor.running = true;
        Quickshell.execDetached(["sh", "-c", `
            t="$1" s="$2"
            gsettings set org.gnome.desktop.interface cursor-theme "$t"
            gsettings set org.gnome.desktop.interface cursor-size "$s"
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$t"
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize "$s"
            d="$HOME/.local/share/icons/default"
            mkdir -p "$d" && printf '[Icon Theme]\\nInherits=%s\\n' "$t" > "$d/index.theme"`, "sh", theme, String(size)]);
    }

    // Hyprland hides the pointer everywhere (desktop too) after the same rest as the ring
    function hideIdle() {
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ cursor = { inactive_timeout = ${Settings.cursorIdle} } })`]);
    }
    Connections {
        target: Settings
        function onCursorIdleChanged() { root.hideIdle(); }
    }

    // Recolored themes are built first; Hyprland's option follows what's on screen
    function update() {
        if ((tint || fix || selfColored) && ready(theme))
            commit();
        else if (tint || selfColored || fix)
            rebuild.restart();
        else
            commit();
    }

    // Built copies on disk (Fixed-, Tinted-), so picking one of them skips the build
    property var built: ({})
    // Hyprland freezes for 100-200 ms loading a theme, so while the accent fades to a new
    // wallpaper's the switch waits until it has settled
    property bool held: false
    function commit() {
        if (Accent.progress < 1 || settle.running)
            return void (held = true);
        held = false;
        apply();
        if (Settings.get("cursor_theme") !== theme)
            Settings.set("cursor_theme", theme);
    }
    Connections {
        target: Accent
        function onProgressChanged() {
            if (Accent.progress >= 1 && root.held)
                settle.restart();
        }
    }
    Timer {
        id: settle
        interval: 250
        onTriggered: if (root.held) root.commit()
    }

    // Later, so a wallpaper's accent fade has begun (the theme follows its target)
    onThemeChanged: Qt.callLater(update)
    Component.onCompleted: apply()

    Process {
        id: scan
        running: true
        // The Rice themes are drawn here, not shipped: built on first run
        command: ["sh", "-c", `[ -d "$HOME/.local/share/icons/Rice-Fluent" ] || "$0" >/dev/null
        for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
            for t in "$d"/*/; do
                t=\${t%/}
                [ -L "$t" ] && continue
                n=\${t##*/}
                # Left-handed variants and themes not wanted for now (Oxygen) stay out of the list
                case "$n" in default|KDE_Classic|rose-pine-hyprcursor|*_lh|*-Right|Oxygen_*) continue ;; Tinted-*|Fixed-*) printf '@%s %s\\n' "$n" "$(cat "$t/partial" 2>/dev/null)"; continue ;; esac
                if [ -d "$t/cursors" ]; then printf '%s\\t%s\\t1\\n' "$n" "$t"
                elif [ -d "$t/hyprcursors" ]; then printf '%s\\t%s\\t0\\n' "$n" "$t"; fi
            done
        done | sort -fu -t "$(printf '\\t')" -k1,1`, Quickshell.shellDir + "/scripts/cursor-dot.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l);
                root.built = {};
                for (const l of lines.filter(l => l.startsWith("@")))
                    root.note(l.slice(1));
                root.themes = lines.filter(l => !l.startsWith("@")).map(l => {
                const [name, path, x] = l.split("\t");
                const [family, style, color] = root.classify(name);
                return { name, path, family, style, color, xcursor: x === "1" };
                });
                prebuild.start();
                preview.command = [Quickshell.shellDir + "/scripts/cursor-preview.py", root.previewDir, ...root.themes.filter(t => t.xcursor).map(t => t.path)];
                preview.running = true;
            }
        }
    }

    Timer {
        id: rebuild
        interval: 50
        onTriggered: {
            if (build.running) {
                // Only the rest of the sizes of an older pick left: drop it
                if (build.shown)
                    build.running = false;
                restart();
                return;
            }
            const script = Quickshell.shellDir + "/scripts/cursor-recolor.py";
            const recolor = root.fix ? [script, root.current.path, "none"] : [script, root.current?.path ?? "", "#" + root.tintHex].concat(root.tint === "accent" ? [] : ["contrast"]);
            build.shown = false;
            build.target = root.theme + String(Accent.cursorTarget);
            // Recolored: the sizes on screen first (Hyprland loads size times the scale rounded up), applied as soon as it's there, then the rest
            build.command = root.selfColored ? [Quickshell.shellDir + "/scripts/cursor-dot.py", "#" + root.tintHex, root.base, "--as", root.theme] : ["sh", "-c", `ONLY_SIZE="$0" "$@" && nice -n 10 "$@"`, root.only, ...recolor];
            build.running = true;
        }
    }
    Process {
        id: build
        property bool shown: false
        // What it builds; the pick may have moved on meanwhile
        property string target: ""
        readonly property bool current: target === root.theme + String(Accent.cursorTarget)
        stdout: SplitParser {
            onRead: line => {
                root.note(line);
                if (line.startsWith("-"))
                    return;
                if (!build.shown) {
                    build.shown = true;
                    if (build.current)
                        root.commit();
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("Cursor build:", line)
        }
        onExited: code => {
            // 15: stopped on purpose, a newer pick took over
            if (code !== 0 && code !== 15)
                console.warn("Cursor build", build.target, "exited with", code);
            if (!build.current)
                rebuild.restart();
            else if (!shown)
                root.commit();
            warm.restart();
        }
    }

    // Strips of each theme's arrow, hand and text cursor for the settings, by theme name
    readonly property string previewDir: Quickshell.cachePath("cursor-previews")
    property var previews: ({})
    // The one on screen in its actual color (recolored copies), once applied
    readonly property string shownPreview: previews[theme] ?? previews[base] ?? ""
    Process {
        id: shownStrip
        stdout: SplitParser {
            onRead: name => root.previews = Object.assign({}, root.previews, { [name]: "file://" + root.previewDir + "/" + name + ".png?" + Date.now() })
        }
    }
    Process {
        id: preview
        stdout: SplitParser {
            onRead: name => root.previews = Object.assign({}, root.previews, { [name]: "file://" + root.previewDir + "/" + name + ".png" })
        }
    }

    // Every theme's Fixed- copy gets built once in the background, so the first pick is instant too
    Process {
        id: prebuild
        function start() {
            const todo = root.themes.filter(t => t.xcursor && !t.name.startsWith("Rice-") && !root.built["Fixed-" + t.name]);
            if (!todo.length || running)
                return;
            command = ["nice", "-n", "15", "sh", "-c", 'for p; do "$0" "$p" none; done', Quickshell.shellDir + "/scripts/cursor-recolor.py", ...todo.map(t => t.path)];
            running = true;
        }
        stdout: SplitParser {
            onRead: line => root.note(line)
        }
    }

    // The other colors of the theme on screen get built in the background, so picking them is instant
    Timer {
        id: warm
        interval: 1000
        onTriggered: {
            if (!root.recolorable)
                return;
            const script = Quickshell.shellDir + "/scripts/cursor-recolor.py", path = root.current.path;
            const hex = c => String(root.tints[c] ?? Accent.cursorTarget).toLowerCase();
            const cmds = ["black", "white", "accent"].filter(c => c !== root.tint).map(c => ["nice", "-n", "15", script, path, hex(c)].concat(c === "accent" ? [] : ["contrast"]));
            warmer.command = ["sh", "-c", cmds.map(c => c.map(a => "'" + a + "'").join(" ")).join("; ")];
            warmer.running = true;
        }
    }
    Process {
        id: warmer
        stdout: SplitParser {
            onRead: line => root.note(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("Cursor build:", line)
        }
    }

    Process {
        running: root.tracking
        command: [Quickshell.shellDir + "/scripts/cursor-pos.py"]
        stdout: SplitParser {
            onRead: data => {
                const p = data.split(" ");
                const nx = Number(p[0]), ny = Number(p[1]), now = Date.now();
                if (!isFinite(nx) || !isFinite(ny))
                    return;
                const dt = Math.max(1, now - root.stamp);
                const k = dt > 60 ? 0 : 0.5;
                if (!isFinite(root.vx) || !isFinite(root.vy))
                    root.vx = root.vy = 0;
                root.vx = k * root.vx + (1 - k) * (dt > 60 ? 0 : (nx - root.x) / dt);
                root.vy = k * root.vy + (1 - k) * (dt > 60 ? 0 : (ny - root.y) / dt);
                root.stamp = now;
                root.x = nx;
                root.y = ny;
                still.restart();
                root.idle = false;
                idleTimer.restart();
            }
        }
    }
    Timer {
        id: still
        interval: 30
        onTriggered: { root.vx = 0; root.vy = 0; }
    }
    Timer {
        id: idleTimer
        interval: Settings.cursorIdle * 1000
        running: Settings.cursorIdle > 0
        onTriggered: root.idle = true
    }

    // Accent copies for every wallpaper get built ahead, one at a time and niced, so paging
    // through wallpapers never waits on a build
    property var walls: []
    Timer {
        id: warmAll
        interval: 3000
        running: root.followsAccent && root.themes.length > 0
        onTriggered: wallList.running = true
    }
    Connections {
        target: root
        function onBaseChanged() { warmAll.restart(); }
        function onOnlyChanged() { warmAll.restart(); }
    }
    Process {
        id: wallList
        command: ["find", Wallpaper.dir, Wallpaper.videoDir, "-type", "f"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.walls = text.trim().split("\n").filter(p => p);
                guess.next();
            }
        }
    }
    Process {
        id: guess
        property string wall: ""
        // Colors still to build for wall
        property var colors: []
        function next() {
            if (colors.length)
                return void make(colors.shift());
            if (!root.walls.length || !root.followsAccent)
                return;
            if (build.running)
                return void warmAll.restart();
            wall = root.walls[0];
            root.walls = root.walls.slice(1);
            // Grayscale ones are black or white, either way round as they can be inverted
            if (Wallpaper.isMono(wall)) {
                colors = [Accent.monoLight, Accent.monoDark];
                return void next();
            }
            const image = Wallpaper.isVideo(wall) ? Wallpaper.videoStill(wall) : Wallpaper.still(wall);
            command = ["nice", "-n", "19"].concat(Accent.analysis(image));
            running = true;
        }
        function make(c) {
            const hex = String(c).slice(1).toLowerCase();
            if (root.ready("Tinted-" + hex + "-" + root.base) || !root.current?.xcursor)
                return void Qt.callLater(next);
            tinter.command = root.selfColored ? ["nice", "-n", "19", Quickshell.shellDir + "/scripts/cursor-dot.py", "#" + hex, root.base, "--as", "Tinted-" + hex + "-" + root.base] : ["nice", "-n", "19", "env", "ONLY_SIZE=" + root.only, Quickshell.shellDir + "/scripts/cursor-recolor.py", root.current.path, "#" + hex];
            tinter.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const c = Accent.predict(guess.wall, text);
                if (c)
                    guess.make(c);
                else
                    Qt.callLater(guess.next);
            }
        }
    }
    Process {
        id: tinter
        stdout: SplitParser {
            onRead: line => root.note(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("Cursor build:", line)
        }
        onExited: guess.next()
    }
}
