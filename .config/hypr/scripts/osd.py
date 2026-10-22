#!/usr/bin/env python3
"""On-screen display: a small pill near the bottom of the screen for volume,
brightness, media, Caps Lock and keyboard layout.

    osd.py daemon [--margin PX]   run the OSD (via respawn.sh from hyprland.lua)
    osd.py volume raise|lower|mute
    osd.py mic mute
    osd.py brightness raise|lower
    osd.py media next|prev|play-pause
    osd.py caps                   show Caps Lock state (bound non-consuming)
    osd.py margin PX              move the pill live, e.g. to find a value
                                  for hardware.lua's osd_margin

Commands are sent to the daemon over a unix socket and the daemon runs the
action itself, so a keypress costs one short Python start and no GTK import.
The layout pill needs no command: the daemon listens to Hyprland's event
socket (Caps Lock switches layout here, grp:caps_toggle).

Fade in/out is Hyprland's layer animation (layer_rule for namespace "osd"),
so the blur behind the pill fades with it. The bar and its percentage glide
to each new value with an Adw.TimedAnimation that restarts from wherever it
currently is, so holding a key never makes it jump.
"""

import os
import socket
import sys

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "osd.sock")


def send(args):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(SOCK)
        s.sendall((" ".join(args) + "\n").encode())
    except OSError:
        sys.exit(f"osd: daemon not running ({SOCK})")
    finally:
        s.close()


if __name__ == "__main__" and sys.argv[1:2] != ["daemon"]:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    send(sys.argv[1:])
    sys.exit(0)

# gtk4-layer-shell has to be loaded before libwayland-client.
PRELOAD = "/usr/lib/libgtk4-layer-shell.so"
if PRELOAD not in os.environ.get("LD_PRELOAD", ""):
    os.environ["LD_PRELOAD"] = PRELOAD
    os.execv(sys.executable, [sys.executable] + sys.argv)

import json
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk
from gi.repository import Gtk4LayerShell as LayerShell

CONFIG = Path.home() / ".config/osd"
TIMEOUT_MS = 700    # how long the pill stays after the last update
GLIDE_MS = 180      # bar/percentage glide to a new value
DEFAULT_MARGIN = 56  # px above the bottom edge; per machine: hardware.lua osd_margin


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def wpctl_state(node):
    out = run("wpctl", "get-volume", node)  # "Volume: 0.55" or "Volume: 0.55 [MUTED]"
    try:
        return float(out.split()[1]), "[MUTED]" in out
    except (IndexError, ValueError):
        return 0.0, False


def main_keyboard():
    try:
        kbs = json.loads(run("hyprctl", "devices", "-j"))["keyboards"]
        return next((k for k in kbs if k.get("main")), kbs[0])
    except (ValueError, KeyError, IndexError, StopIteration):
        return {}


class Osd(Adw.Application):
    def __init__(self, margin):
        super().__init__(application_id="rice.osd", flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.margin = margin
        self.kind = None        # what the pill currently shows ("volume", "text", ...)
        self.shown = 0.0        # bar value on screen right now
        self.hide_id = 0
        self.last_layout = None

    def do_activate(self):
        self.hold()
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        self.load_css()

        win = self.win = Gtk.Window(application=self)
        LayerShell.init_for_window(win)
        LayerShell.set_namespace(win, "osd")
        LayerShell.set_layer(win, LayerShell.Layer.OVERLAY)
        LayerShell.set_anchor(win, LayerShell.Edge.BOTTOM, True)
        LayerShell.set_margin(win, LayerShell.Edge.BOTTOM, self.margin)
        LayerShell.set_exclusive_zone(win, -1)
        LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.NONE)

        box = Gtk.Box(spacing=12, css_classes=["pill"])
        self.icon = Gtk.Image()
        self.bar = Gtk.ProgressBar(valign=Gtk.Align.CENTER)
        self.value = Gtk.Label(css_classes=["value"], width_chars=3, xalign=1)
        self.text = Gtk.Label(css_classes=["text"], max_width_chars=40,
                              ellipsize=3)  # Pango.EllipsizeMode.END
        for w in (self.icon, self.bar, self.value, self.text):
            box.append(w)
        win.set_child(box)

        target = Adw.CallbackAnimationTarget.new(self.set_shown)
        self.anim = Adw.TimedAnimation.new(self.bar, 0, 0, GLIDE_MS, target)
        self.anim.set_easing(Adw.Easing.EASE_OUT_CUBIC)

        self.listen_commands()
        self.listen_hyprland()

    # -- styling ------------------------------------------------------------------

    def load_css(self):
        self.css = Gtk.CssProvider()
        self.css.load_from_path(str(CONFIG / "style.css"))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        # theme-apply.py rewrites colors.css on every accent change.
        self.monitor = Gio.File.new_for_path(str(CONFIG / "colors.css")).monitor_file(
            Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self.on_colors_changed)

    def on_colors_changed(self, _mon, _file, _other, event):
        if event == Gio.FileMonitorEvent.CHANGES_DONE_HINT:
            self.css.load_from_path(str(CONFIG / "style.css"))

    # -- showing --------------------------------------------------------------------

    def set_shown(self, v):
        self.shown = v
        self.bar.set_fraction(min(v, 1.0))
        self.value.set_label(str(round(v * 100)))

    def show_bar(self, kind, icon, value, muted=False):
        # Glide only when the pill already shows this bar; otherwise start
        # at the value so switching from volume to brightness doesn't slide.
        if self.kind == kind and self.win.get_visible():
            self.anim.pause()
            self.anim.set_value_from(self.shown)
            self.anim.set_value_to(value)
            self.anim.play()
        else:
            self.anim.pause()
            self.set_shown(value)
        self.kind = kind
        self.icon.set_from_icon_name(icon)
        self.bar.set_visible(True)
        self.value.set_visible(True)
        self.text.set_visible(False)
        box = self.win.get_child()
        (box.add_css_class if muted else box.remove_css_class)("muted")
        self.present()

    def show_text(self, icons, text):
        """icons: one name or a fallback list (icon themes differ per machine)."""
        self.anim.pause()
        self.kind = "text"
        names = [icons] if isinstance(icons, str) else icons
        self.icon.set_from_gicon(Gio.ThemedIcon.new_from_names(names))
        self.text.set_label(text)
        self.bar.set_visible(False)
        self.value.set_visible(False)
        self.text.set_visible(True)
        self.win.get_child().remove_css_class("muted")
        self.present()

    def present(self):
        self.win.set_visible(True)
        if self.hide_id:
            GLib.source_remove(self.hide_id)
        self.hide_id = GLib.timeout_add(TIMEOUT_MS, self.hide)

    def hide(self):
        self.hide_id = 0
        self.win.set_visible(False)
        return False

    # -- actions --------------------------------------------------------------------

    def volume(self, node, action):
        if action == "raise":
            run("wpctl", "set-volume", "-l", "1", node, "5%+")
        elif action == "lower":
            run("wpctl", "set-volume", node, "5%-")
        elif action == "mute":
            run("wpctl", "set-mute", node, "toggle")
        vol, muted = wpctl_state(node)
        if node == "@DEFAULT_AUDIO_SOURCE@":
            icon = "microphone-sensitivity-muted-symbolic" if muted else "microphone-sensitivity-high-symbolic"
            self.show_bar("mic", icon, vol, muted)
            return
        if muted or vol == 0:
            icon = "audio-volume-muted-symbolic"
        else:
            icon = f"audio-volume-{'low' if vol < 0.34 else 'medium' if vol < 0.67 else 'high'}-symbolic"
        self.show_bar("volume", icon, vol, muted)

    def brightness(self, action):
        # Same curve as before swayosd: exponent 4, never below 2%.
        step = "5%+" if action == "raise" else "5%-"
        out = run("brightnessctl", "-e4", "-n2", "-m", "set", step)
        try:
            pct = int(out.split(",")[3].rstrip("%"))
        except (IndexError, ValueError):
            return  # no backlight (desktop monitor)
        self.show_bar("brightness", "display-brightness-symbolic", pct / 100)

    def media(self, action):
        run("playerctl", {"prev": "previous"}.get(action, action))
        # The player needs a moment to publish the new track / state.
        GLib.timeout_add(250, self.show_media)

    def show_media(self):
        status = run("playerctl", "status")
        if not status:
            return False
        title = run("playerctl", "metadata", "--format", "{{artist}} — {{title}}").strip(" —")
        icon = "media-playback-pause-symbolic" if status == "Paused" else "media-playback-start-symbolic"
        self.show_text(icon, title or status)
        return False

    def caps(self):
        # Bound non-consuming on key press: let xkb flip the state first.
        def show():
            on = main_keyboard().get("capsLock", False)
            # capslock-* is Tela (laptop); Breeze (desktop) only has input-caps-on.
            self.show_text([f"capslock-{'enabled' if on else 'disabled'}-symbolic",
                            "input-caps-on-symbolic"],
                           f"Caps {'on' if on else 'off'}")
            return False
        GLib.timeout_add(50, show)

    def layout(self, name):
        if name == self.last_layout:
            return  # every keyboard device reports the same switch
        first = self.last_layout is None
        self.last_layout = name
        if not first:
            label = {"English": "EN", "Russian": "RU"}.get(name.split()[0], name[:2].upper())
            self.show_text("input-keyboard-symbolic", label)

    def command(self, line):
        args = line.split()
        match args:
            case ["volume", action]:
                self.volume("@DEFAULT_AUDIO_SINK@", action)
            case ["mic", "mute"]:
                self.volume("@DEFAULT_AUDIO_SOURCE@", "mute")
            case ["brightness", action]:
                self.brightness(action)
            case ["media", action]:
                self.media(action)
            case ["caps"]:
                self.caps()
            case ["margin", px] if px.isdigit():
                self.margin = int(px)
                LayerShell.set_margin(self.win, LayerShell.Edge.BOTTOM, self.margin)
                self.show_text("input-keyboard-symbolic", f"margin {px}")
            case _:
                print(f"osd: unknown command {line!r}", file=sys.stderr)

    # -- sockets --------------------------------------------------------------------

    def listen_commands(self):
        try:
            os.unlink(SOCK)
        except FileNotFoundError:
            pass
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(SOCK)
        self.server.listen(8)
        GLib.io_add_watch(self.server.fileno(), GLib.IO_IN, self.on_client)

    def on_client(self, *_):
        conn, _ = self.server.accept()
        with conn:
            conn.settimeout(0.5)
            data = b""
            try:
                while not data.endswith(b"\n"):
                    chunk = conn.recv(256)
                    if not chunk:
                        break
                    data += chunk
            except OSError:
                pass
        for line in data.decode(errors="replace").splitlines():
            self.command(line)
        return True

    def listen_hyprland(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr",
                            os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket2.sock")
        self.events = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.events.connect(path)
        self.events_buf = b""
        # Seed the current layout so the first real switch shows up.
        self.last_layout = main_keyboard().get("active_keymap")
        GLib.io_add_watch(self.events.fileno(), GLib.IO_IN | GLib.IO_HUP, self.on_event)

    def on_event(self, _fd, cond):
        chunk = self.events.recv(4096)
        if not chunk:  # Hyprland is gone; respawn.sh stops too
            self.quit()
            return False
        self.events_buf += chunk
        *lines, self.events_buf = self.events_buf.split(b"\n")
        for raw in lines:
            line = raw.decode(errors="replace")
            if line.startswith("activelayout>>"):
                self.layout(line.split(",", 1)[-1])
        return True


if __name__ == "__main__":
    margin = DEFAULT_MARGIN
    if "--margin" in sys.argv:
        try:
            margin = int(sys.argv[sys.argv.index("--margin") + 1])
        except (IndexError, ValueError):
            pass
    Osd(margin).run([sys.argv[0]])
