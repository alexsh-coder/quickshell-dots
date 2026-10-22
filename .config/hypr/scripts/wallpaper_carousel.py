#!/usr/bin/env python3
"""Horizontal wallpaper carousel: current wallpaper centered, neighbors
peeking in on both sides and dissolving to transparency (revealing the
blurred desktop, not a dark fill), animated slide on Left/Right that loops
forever. The settled page is pushed live to the desktop via awww, after a
short debounce once the user stops paging.

Infinite scroll is an illusion: only SLOT_COUNT real widgets exist. A single
persistent Adw.SpringAnimation drives one unbounded float (raw_target, +-1.0
per keypress, never clamped) via Adw.CallbackAnimationTarget. Every tick,
whole-page boundary crossings rebase which file each slot shows and shift
the "committed" reference point by exactly one page -- since the repaint
matches what's already on screen, the rebase is invisible. Because the
animation itself is redirected in place (set_value_to() on a still-playing
spring, never play() again, which would restart it from zero velocity) and
never torn down mid-flight, paging speed is bounded only by keyboard repeat,
not by waiting for each page to settle, and the eased curve is never
truncated the way a discrete page-changed snap-back would truncate it.

Every slot uses the same plain, ungraded disk-cached thumbnail (Pillow
cover-crop/resize), instead of the full-resolution source file -- this
avoids decoding a 4K image on every page settle (the previous source of
paging stutter). Transparency toward the window edge comes ONLY from the
per-frame animated widget opacity in layout_slots(), which is a continuous
function of distance from center. An earlier version baked an extra
per-pixel alpha gradient into the side-slot thumbnails themselves; that
gradient is swapped in as a discrete image-source change exactly at each
whole-page rebase, which under the continuous widget-opacity fade still
produced a visible one-frame pop -- so it's gone, and only the continuous
widget-level fade remains.
"""

import hashlib
import json
import os
import signal
import subprocess
import time
from pathlib import Path
from urllib.parse import quote

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gsk", "4.0")
gi.require_version("Graphene", "1.0")
from gi.repository import Adw, Gdk, Gio, GLib, Graphene, Gsk, Gtk
from PIL import Image

WALLPAPER_DIR = Path("/home/lab-qs/Pictures/wallpapers")
CACHE_DIR = Path.home() / ".cache" / "wallpaper_carousel"
PAGE_ASPECT = 16 / 9  # matches the wallpapers' native aspect ratio
WINDOW_WIDTH = 840
WINDOW_HEIGHT = 280
SLOT_SPACING = 16
TRANSITION_TYPE = "center"  # grow-from-center, not a directional page-wipe
TRANSITION_DURATION = "0.66"
TRANSITION_FPS = "60"
COMMIT_DEBOUNCE_MS = 300  # real desktop apply waits this long after the last keypress
MAX_LEAD_PAGES = 3.0  # token-bucket burst capacity: quick multi-taps feel instant
MAX_PAGES_PER_SEC = 6.0  # token-bucket sustained refill rate: caps held-key cruise speed

THUMB_SCALE = 1.6  # thumbnail pixel size relative to the on-screen page
THUMB_HEIGHT = int(WINDOW_HEIGHT * THUMB_SCALE)
THUMB_WIDTH = int(THUMB_HEIGHT * PAGE_ASPECT)

FADE_DISTANCE_COEF = 0.35   # per-frame widget-opacity fade during scroll

SLOT_COUNT = 5
CENTER_SLOT = SLOT_COUNT // 2

BASE_CSS = """
window {
    background-color: transparent;
    box-shadow: none;
    border: none;
}
decoration {
    background-color: transparent;
    box-shadow: none;
    border: none;
    border-radius: 0;
}
.page {
    background-size: cover;
    background-position: center;
    background-repeat: no-repeat;
    border-radius: 12px;
}
"""

EDGE_FADE_PIXELS = 140  # fade ramps across this many pixels from the WINDOW edge
CORNER_DEADZONE_PIXELS = 18  # kept fully transparent -- must exceed .page's 12px border-radius


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _hyprctl_json(*args: str):
    try:
        out = subprocess.run(
            ["hyprctl", "-j", *args], capture_output=True, text=True, timeout=2
        ).stdout
        return json.loads(out)
    except Exception:
        return None


def _visible_workspace_id():
    """The workspace id actually on screen right now, on the focused
    monitor. `hyprctl activeworkspace` is NOT enough on its own: a
    special/scratchpad workspace (e.g. this box's Super+S "magic"
    scratchpad) overlays the regular one, and `activeworkspace` keeps
    reporting the regular workspace UNDERNEATH even while the special one
    is what's actually visible and focused -- confirmed via `hyprctl -j
    monitors`, which carries both `activeWorkspace` and, separately,
    `specialWorkspace` (present with a non-empty name only while toggled
    visible) per monitor. Prefer the special one when it's showing.
    """
    monitors = _hyprctl_json("monitors")
    if not monitors:
        return None
    for m in monitors:
        if not m.get("focused"):
            continue
        special = m.get("specialWorkspace") or {}
        if special.get("name"):
            return special.get("id")
        return (m.get("activeWorkspace") or {}).get("id")
    return None


def close_other_instances() -> bool:
    """Enforce single-instance: kill any other running copy of this exact
    script before creating our own window. Without this, Super+W could
    stack multiple overlapping popups, and pressing it while a popup is
    already open on another workspace would just switch you to that
    workspace instead of closing it and opening a fresh one where you
    actually are. Killing the OS process (rather than relying on
    GApplication's D-Bus single-instance activation) is deliberate: this
    script is edited often, and D-Bus activation would re-present an
    already-running process's OLD in-memory code instead of starting a
    genuinely fresh one -- see the wallpaper_carousel_super_w memory note
    on the singleton staleness bug this caused during development.

    Returns True if an existing popup was already open on the CURRENT
    workspace -- it was closed and the caller should exit immediately
    instead of opening a new one, so a second Super+W press on the same
    workspace toggles the popup off rather than closing-then-reopening
    it (which just flickered pointlessly). Returns False if no popup was
    open, or the only one open lived on a different workspace (closed
    to make room -- the caller should open a fresh one here).
    """
    my_pid = os.getpid()
    script = str(Path(__file__).resolve())
    try:
        out = subprocess.run(
            ["pgrep", "-f", script], capture_output=True, text=True, timeout=2
        ).stdout
    except Exception:
        return False
    victims = {int(p) for p in out.split() if p.isdigit() and int(p) != my_pid}
    if not victims:
        return False

    same_workspace = False
    clients = _hyprctl_json("clients")
    active_id = _visible_workspace_id()
    if clients is not None and active_id is not None:
        for c in clients:
            if "WallpaperCarousel" not in c.get("class", ""):
                continue
            if c.get("pid") in victims and c.get("workspace", {}).get("id") == active_id:
                same_workspace = True

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    remaining = set(victims)
    deadline = time.monotonic() + 0.3
    while remaining and time.monotonic() < deadline:
        remaining = {pid for pid in remaining if _pid_alive(pid)}
        if remaining:
            time.sleep(0.02)
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    return same_workspace


def current_wallpaper() -> str | None:
    try:
        out = subprocess.run(["awww", "query"], capture_output=True, text=True, timeout=2).stdout
        marker = "image: "
        idx = out.find(marker)
        if idx == -1:
            return None
        return out[idx + len(marker):].strip()
    except Exception:
        return None


def _cache_key(path: Path) -> str:
    st = path.stat()
    raw = f"{path}:{st.st_mtime_ns}:{st.st_size}"
    return hashlib.sha1(raw.encode()).hexdigest()[:16]


def _cover_crop_resize(img: Image.Image, width: int, height: int) -> Image.Image:
    src_ratio = img.width / img.height
    dst_ratio = width / height
    if src_ratio > dst_ratio:
        new_height = img.height
        new_width = int(new_height * dst_ratio)
        x0 = (img.width - new_width) // 2
        img = img.crop((x0, 0, x0 + new_width, new_height))
    else:
        new_width = img.width
        new_height = int(new_width / dst_ratio)
        y0 = (img.height - new_height) // 2
        img = img.crop((0, y0, new_width, y0 + new_height))
    return img.resize((width, height), Image.Resampling.LANCZOS)


def _thumb_path(path: Path) -> Path:
    return CACHE_DIR / f"{_cache_key(path)}-plain.png"


def ensure_thumbnail(path: Path) -> Path:
    out = _thumb_path(path)
    if out.exists():
        return out
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with Image.open(path) as im:
        base = _cover_crop_resize(im.convert("RGB"), THUMB_WIDTH, THUMB_HEIGHT)
    base.save(out, "PNG")
    return out


class EdgeFadeBin(Gtk.Widget):
    """Wraps a single child and masks it with a symmetric horizontal
    linear-gradient alpha ramp that fades to transparent at BOTH window
    edges (0..EDGE_FADE_PIXELS and WINDOW_WIDTH-EDGE_FADE_PIXELS..
    WINDOW_WIDTH), fully opaque in between. Applied to every slot
    uniformly, not just the two "peeking neighbor" slots -- see below.

    This GTK build has no CSS `mask-image` support (verified: the CSS
    parser rejects it outright), so the mask is built by hand each frame
    via Gtk.Snapshot.push_mask()+append_linear_gradient() -- cheap, GPU
    composited, no per-pixel Python/Pillow work.

    The gradient is anchored to the WINDOW's fixed pixel edges (screen_x
    is updated every frame by CarouselWindow._on_get_child_position), NOT
    to this widget's own local width. Each slot box is page_width
    (~500px) wide -- nearly as wide as the whole popup -- and almost all
    of it sits off-screen, clipped away by the window bounds; only a
    ~100-170px sliver near a window edge is ever actually visible. A
    gradient built as a fraction of the widget's OWN width faded almost
    entirely within that clipped, invisible region, so the visible sliver
    was already back to full opacity -- a real bug, confirmed by
    computing where the visible slice falls in local coordinates.

    The first CORNER_DEADZONE_PIXELS of the ramp are pinned to pure
    transparent (not just "very low alpha") because `.page` has a 12px
    border-radius: right at a window edge, the rounded-corner clip sits
    close enough to the edge that a smoothly-ramping-from-zero gradient
    still gives it a few percent of alpha there, which reads as a faint
    but distinctly edged sliver once you look for it (the clip boundary
    itself is always crisp; only the fill inside it fades). Keeping a
    flat zero-alpha margin wider than the corner radius guarantees the
    corner curve is never partially visible.

    An earlier version keyed the fade side ("left"/"right") to slot ROLE
    (i < CENTER_SLOT vs i > CENTER_SLOT), fixed at construction, and left
    the CENTER slot (i == CENTER_SLOT) unmasked entirely on the theory
    that only the two peeking neighbors ever approach an edge. That's
    false: mid-animation, the outgoing center image slides most of the
    way to an edge (still fully opaque, hard window-clipped, since it's
    still the unmasked center-role widget) and only starts fading at the
    exact instant of the whole-page rebase, when its file identity hands
    off to a permanently-masked neighbor slot -- a visible pop ("goes
    over the mask, then suddenly under it"). Masking every slot with the
    SAME symmetric both-edges gradient, driven purely by each slot's
    current screen position rather than a fixed role, removes that
    special case entirely: whichever slot is near an edge fades there,
    full stop, regardless of which slot index or file it happens to be.
    """

    def __init__(self, child: Gtk.Widget):
        super().__init__()
        self.set_layout_manager(Gtk.BinLayout())
        self.screen_x = 0.0  # this widget's current x, set by _on_get_child_position
        child.set_parent(self)

    def do_snapshot(self, snapshot):
        width = self.get_width()
        height = self.get_height()
        if width <= 0 or height <= 0:
            return
        bounds = Graphene.Rect().init(0, 0, width, height)
        p0 = Graphene.Point().init(0.0 - self.screen_x, height / 2)
        p1 = Graphene.Point().init(WINDOW_WIDTH - self.screen_x, height / 2)
        transparent = Gdk.RGBA()
        transparent.parse("rgba(255,255,255,0)")
        opaque = Gdk.RGBA()
        opaque.parse("rgba(255,255,255,1)")
        inner = EDGE_FADE_PIXELS / WINDOW_WIDTH
        dead = CORNER_DEADZONE_PIXELS / WINDOW_WIDTH
        stops = []
        for offset, color in (
            (0.0, transparent),
            (dead, transparent),
            (inner, opaque),
            (1.0 - inner, opaque),
            (1.0 - dead, transparent),
            (1.0, transparent),
        ):
            stop = Gsk.ColorStop()
            stop.offset = offset
            stop.color = color
            stops.append(stop)
        snapshot.push_mask(Gsk.MaskMode.ALPHA)
        snapshot.append_linear_gradient(bounds, p0, p1, stops)
        snapshot.pop()
        child = self.get_first_child()
        if child is not None:
            self.snapshot_child(child, snapshot)
        snapshot.pop()


class CarouselWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_size_request(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_resizable(False)

        self.files = sorted(
            p for p in WALLPAPER_DIR.iterdir()
            if p.suffix.lower() in (".jpg", ".jpeg", ".png")
        )
        self.file_index = 0
        self.thumb_cache: dict[Path, Path] = {}

        current = current_wallpaper()
        if current and current in (str(p) for p in self.files):
            self.file_index = [str(p) for p in self.files].index(current)

        self.page_height = WINDOW_HEIGHT
        self.page_width = int(self.page_height * PAGE_ASPECT)

        # Critically damped (damping ratio == 1): still a real spring-driven
        # ease-in/ease-out curve, just no overshoot/bounce past the target.
        self.spring_params = Adw.SpringParams.new(1.0, 0.6, 200)
        self.raw_value = 0.0        # current animated coordinate
        self.raw_target = 0.0       # +-1.0 per accepted keypress (see _take_page_token)
        self.committed_offset = 0.0  # whole-integer steps only
        self.animation: Adw.SpringAnimation | None = None
        self.commit_timeout_id: int | None = None
        self._commit_pending = False
        self._page_tokens = MAX_LEAD_PAGES
        self._token_bucket_last = time.monotonic()

        # Gtk.Overlay, not Gtk.Fixed: overlay children are positioned via the
        # "get-child-position" signal and, by GTK4 design, never contribute
        # to the overlay's own measured size -- unlike Gtk.Fixed (whose
        # measure() is delegated to its internal GtkFixedLayout and reports
        # the bounding box of all child positions), so a slot sliding out
        # past the window edge for the "peeking" effect can never make the
        # popup itself grow/reflow mid-animation.
        self.overlay = Gtk.Overlay()
        spacer = Gtk.Box()
        spacer.set_size_request(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.overlay.set_child(spacer)
        self.overlay.connect("get-child-position", self._on_get_child_position)

        self.pages: list[Gtk.Box] = []
        self._slot_of_widget: dict[Gtk.Box, int] = {}
        self._local = float(CENTER_SLOT)  # current slot-space position, set by layout_slots
        for i in range(SLOT_COUNT):
            box = Gtk.Box()
            box.set_size_request(self.page_width, self.page_height)
            box.add_css_class("page")
            box.add_css_class(f"slot-{i}")
            widget = EdgeFadeBin(box)
            self.overlay.add_overlay(widget)
            self.pages.append(box)
            self._slot_of_widget[widget] = i

        self.css_provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Only the slots visible right now are generated synchronously, so
        # opening the popup doesn't stall on thumbnailing the whole folder.
        for i in range(SLOT_COUNT):
            self.get_thumb(self.slot_file(i))
        self.refresh_slot_images()
        self._warm_queue = iter(p for p in self.files if p not in self.thumb_cache)
        GLib.idle_add(self._warm_step)

        self.set_content(self.overlay)

        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

    def get_thumb(self, path: Path) -> Path:
        cached = self.thumb_cache.get(path)
        if cached is None:
            cached = ensure_thumbnail(path)
            self.thumb_cache[path] = cached
        return cached

    def _warm_step(self):
        path = next(self._warm_queue, None)
        if path is None:
            return False
        self.get_thumb(path)
        return True

    def slot_file(self, slot: int) -> Path:
        return self.files[(self.file_index + (slot - CENTER_SLOT)) % len(self.files)]

    def refresh_slot_images(self):
        rules = []
        for i in range(SLOT_COUNT):
            thumb = self.get_thumb(self.slot_file(i))
            rules.append(
                f'.slot-{i} {{ background-image: url("file://{quote(str(thumb))}"); }}'
            )
        self.css_provider.load_from_string(BASE_CSS + "\n".join(rules))

    def start_at_current(self):
        self.layout_slots(0.0)

    def on_scroll_tick(self, value, *_user_data):
        self.raw_value = value
        frac = value - self.committed_offset
        rebased = False
        while frac >= 1.0:
            self.file_index = (self.file_index + 1) % len(self.files)
            self.committed_offset += 1.0
            frac -= 1.0
            rebased = True
        while frac <= -1.0:
            self.file_index = (self.file_index - 1) % len(self.files)
            self.committed_offset -= 1.0
            frac += 1.0
            rebased = True
        if rebased:
            self.refresh_slot_images()
        self.layout_slots(frac)

    def layout_slots(self, frac: float):
        local = CENTER_SLOT + frac
        for i, box in enumerate(self.pages):
            # Continuous function of distance for every slot, including the
            # one becoming the center -- no special-cased hard cut to 1.0.
            # A hard cut created a visible opacity discontinuity at the exact
            # instant "nearest" flipped (e.g. jumping 0.83 -> 1.0 in one
            # frame), which read as an abrupt snap rather than a fade.
            distance = abs(local - i)
            box.set_opacity(max(0.0, 1.0 - distance * FADE_DISTANCE_COEF))
        self._local = local
        self.overlay.queue_allocate()

    def _on_get_child_position(self, overlay, widget, allocation):
        i = self._slot_of_widget[widget]
        step = self.page_width + SLOT_SPACING
        base_x = (WINDOW_WIDTH - self.page_width) / 2
        y = (WINDOW_HEIGHT - self.page_height) / 2
        allocation.x = round(base_x + (i - self._local) * step)
        allocation.y = round(y)
        allocation.width = self.page_width
        allocation.height = self.page_height
        widget.screen_x = allocation.x
        widget.queue_draw()  # force do_snapshot to re-run with the fresh screen_x
        return True

    def _start_animation(self, value_from: float, value_to: float, initial_velocity: float = 0.0):
        target = Adw.CallbackAnimationTarget.new(self.on_scroll_tick)
        anim = Adw.SpringAnimation.new(self, value_from, value_to, self.spring_params, target)
        anim.set_initial_velocity(initial_velocity)
        anim.connect("done", self._on_animation_done)
        self.animation = anim
        anim.play()

    def _retarget_animation(self):
        if self.animation is not None and self.animation.get_state() == Adw.AnimationState.PLAYING:
            # Adw.SpringAnimation evaluates its closed-form position from
            # (value-from, initial-velocity, elapsed time since play()), so
            # calling set_value_to() alone while playing does NOT preserve
            # continuity -- it re-solves that same formula for the new
            # target at the SAME elapsed time, which is mathematically a
            # different curve and jumps the reported value immediately
            # (worse the longer the animation has already been running).
            # That was the exact "instant switch, no visible slide" bug.
            # The only way to redirect a playing spring smoothly is to
            # manually splice in a brand new animation that starts from the
            # old one's current position and velocity -- this IS the
            # interpolation: matching position and velocity at the seam
            # means the two curves join with no discontinuity.
            current_value = self.animation.get_value()
            current_velocity = self.animation.get_velocity()
            self.animation.pause()  # stop the old one ticking independently
            self._start_animation(current_value, self.raw_target, current_velocity)
        else:
            self._start_animation(self.raw_value, self.raw_target)

    def on_key_pressed(self, controller, keyval, keycode, state):
        name = Gdk.keyval_name(keyval)
        if name == "Escape":
            self.close()
            return True
        if name in ("Right", "Left"):
            delta = 1.0 if name == "Right" else -1.0
            if self._take_page_token():
                self.raw_target += delta
                self._retarget_animation()
            # Even a dropped-for-rate-limit press still counts as "the user
            # is actively interacting" for debounce purposes.
            self._schedule_commit()
            return True
        return False

    def _take_page_token(self) -> bool:
        """Token-bucket rate limiter, in real wall-clock time.

        A fixed distance cap on the target (e.g. "at most N pages ahead of
        what's on screen") doesn't actually bound velocity: as soon as any
        progress is made the cap slides forward with it, so a held key
        settles into a sustained pursuit whose cruise speed just tracks
        however fast key-repeat events arrive -- at OS auto-repeat rates
        (20-30/s) that's fast enough to move more than a page between two
        animation frames, which is exactly the "teleports, no visible
        swipe" symptom. Capping the rate pages can be REQUESTED at, in real
        seconds, bounds the sustained cruise speed the spring is ever asked
        to chase, independent of frame rate or how fast key-repeat fires.
        A small burst bucket keeps quick double/triple-taps feeling instant.
        """
        now = time.monotonic()
        elapsed = now - self._token_bucket_last
        self._token_bucket_last = now
        self._page_tokens = min(MAX_LEAD_PAGES, self._page_tokens + elapsed * MAX_PAGES_PER_SEC)
        if self._page_tokens < 1.0:
            return False
        self._page_tokens -= 1.0
        return True

    def _schedule_commit(self):
        if self.commit_timeout_id is not None:
            GLib.source_remove(self.commit_timeout_id)
        self.commit_timeout_id = GLib.timeout_add(COMMIT_DEBOUNCE_MS, self._on_commit_timeout)

    def _on_commit_timeout(self):
        self.commit_timeout_id = None
        if self.animation is not None and self.animation.get_state() == Adw.AnimationState.PLAYING:
            # Still settling after a heavy fling -- apply once it's done instead.
            self._commit_pending = True
        else:
            self._apply_wallpaper()
        return GLib.SOURCE_REMOVE

    def _on_animation_done(self, animation):
        if animation is not self.animation:
            return  # stale signal from an animation a later keypress superseded
        if self._commit_pending:
            self._commit_pending = False
            self._apply_wallpaper()

    def _apply_wallpaper(self):
        subprocess.Popen([
            "awww", "img", str(self.files[self.file_index]),
            "--transition-type", TRANSITION_TYPE,
            "--transition-duration", TRANSITION_DURATION,
            "--transition-fps", TRANSITION_FPS,
        ])
        # Mirror to the SDDM login screen background.
        subprocess.Popen([
            str(Path(__file__).resolve().parent / "wallpaper-sync.sh"),
            str(self.files[self.file_index]),
        ])
        # Re-derive the accent color and fade Waybar/borders/etc. over to it.
        subprocess.Popen([
            str(Path(__file__).resolve().parent / "theme-apply.py"),
            str(self.files[self.file_index]),
        ])


class CarouselApp(Adw.Application):
    def __init__(self):
        # NON_UNIQUE: without it, Gio.Application registers as a D-Bus
        # singleton keyed by application_id -- a second `python3
        # wallpaper_carousel.py` launch (e.g. a second Super+W press) would
        # silently skip creating a new process and just re-present the
        # FIRST process's already-constructed window instead, which is
        # still running whatever code was loaded when THAT process
        # started. That makes every code change look like it "didn't take"
        # or "came back" until the original process happens to be killed --
        # exactly the bug that made the edge-fade and opacity-pop fixes
        # appear to revert. This is a one-shot popup; every invocation
        # should be an independent, fully fresh process.
        super().__init__(
            application_id="dev.local.WallpaperCarousel",
            flags=Gio.ApplicationFlags.NON_UNIQUE,
        )
        self.window = None

    def do_activate(self):
        if self.window is None:
            self.window = CarouselWindow(self)
            self.window.start_at_current()
            self.window.present()
        else:
            self.window.present()


if __name__ == "__main__":
    if not close_other_instances():
        CarouselApp().run(None)
