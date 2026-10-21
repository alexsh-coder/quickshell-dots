#!/usr/bin/env python3
# Reads and toggles the like button of Spotify's now playing bar over AT-SPI.
# Spotify has to start with ACCESSIBILITY_ENABLED=1 to expose its UI.
# Prints "liked<TAB>title", "unliked<TAB>title" or "none" when the state changes;
# reads "toggle" lines on stdin. Elements are found by structure, not by label,
# so it works whatever the client language.

import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib  # noqa: E402


def children(o):
    for i in range(o.get_child_count()):
        c = o.get_child_at_index(i)
        if c:
            yield c


def walk(o):
    stack = [o]
    while stack:
        o = stack.pop()
        yield o
        stack.extend(reversed(list(children(o))))


def attrs(o):
    return o.get_attributes() or {}


def spotify():
    desktop = Atspi.get_desktop(0)
    for app in children(desktop):
        try:
            with open(f"/proc/{app.get_process_id()}/comm") as f:
                if f.read().strip() == "spotify":
                    return app
        except OSError:
            pass
    return None


# The bar is the <aside> whose first child is the now playing widget: cover, title link, artist links, like button
def find_widget():
    app = spotify()
    if not app:
        return None
    for o in walk(app):
        if o.get_role_name() == "landmark" and attrs(o).get("tag") == "aside":
            first = next(children(o), None)
            if first and first.get_role_name() == "landmark" and button(first):
                return first
    return None


def button(widget):
    return next((c for c in children(widget) if attrs(c).get("tag") == "button"), None)


def title(widget):
    for o in walk(widget):
        if o.get_role_name() == "link":
            return o.get_name() or ""
    return ""


def is_liked(btn):
    return "bright-accent" in attrs(btn).get("class", "")


def find_in(root, pred, timeout=3):
    end = time.time() + timeout
    while time.time() < end:
        for o in walk(root):
            if pred(o):
                return o
        time.sleep(0.1)
    return None


class Watcher:
    def __init__(self):
        self.widget = None
        self.last = None

    def read(self):
        try:
            if self.widget is None or button(self.widget) is None:
                self.widget = find_widget()
            if self.widget is None:
                return None
            btn = button(self.widget)
            return ("liked" if is_liked(btn) else "unliked"), title(self.widget)
        except GLib.Error:
            self.widget = None
            return None

    def report(self):
        state = self.read()
        line = "\t".join(state) if state else "none"
        if line != self.last:
            self.last = line
            print(line, flush=True)
        return state

    def poll(self):
        state = self.report()
        # Rescanning the whole window is the costly part, so back off while Spotify isn't there
        GLib.timeout_add(1000 if state else 5000, self.poll)
        return False

    def toggle(self):
        state = self.read()
        if not state:
            return
        btn = button(self.widget)
        btn.do_action(0)
        # Liking is one press; once liked the button opens the playlist picker instead,
        # where Liked Songs is the first checkbox and the confirm button is the last one
        if state[0] == "liked":
            app = spotify()
            menu = app and find_in(app, lambda o: o.get_role_name() == "menu")
            item = menu and find_in(menu, lambda o: o.get_role_name() == "check menu item")
            if not item:
                return
            # The confirm button only shows up once something has changed
            dialog = menu.get_parent().get_parent()
            buttons = lambda: [o for o in walk(dialog) if attrs(o).get("tag") == "button"]
            before = len(buttons())
            item.do_action(0)
            end = time.time() + 3
            while time.time() < end:
                now = buttons()
                if len(now) > before:
                    now[-1].do_action(0)
                    break
                time.sleep(0.1)
        # Always answer a toggle, so a press that didn't take puts the heart back
        self.last = None
        GLib.timeout_add(800, lambda: self.report() and False)


def main():
    w = Watcher()

    def on_input(src, cond):
        line = sys.stdin.readline()
        if not line:
            loop.quit()
            return False
        if line.strip() == "toggle":
            w.toggle()
        return True

    loop = GLib.MainLoop()
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, on_input)
    w.poll()
    loop.run()


if __name__ == "__main__":
    main()
