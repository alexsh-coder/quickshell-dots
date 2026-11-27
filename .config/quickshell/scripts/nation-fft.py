#!/usr/bin/env python3
# Bass spectrum for the Nation ring, the way Trap Nation's After Effects template builds it:
# a linear bass spectrum (bent into a circle and mirrored by the QML side), taken over several
# window lengths. The longest window is the steady white ring, shorter ones react faster and
# become the coloured layers behind it.
# The frequency span follows the track: it covers the stretch of 15-250 Hz that holds most of the
# recent bass energy, so a sped-up track whose bass sits higher still fills the whole circle.
# Prints one line per frame at 60 fps: layers split by "|", points by ";", values 0..1000.
# Usage: nation-fft.py [RAW_S16_MONO_48K_FILE]   (no file: capture what the speakers play)

import os
import select
import subprocess
import sys

import numpy as np

RATE = 48000
FPS = 60
HOP = RATE // FPS
WINDOWS_MS = [170, 160, 150, 140, 130, 120]
NFFT = 1 << 14
POINTS = 64
# Search range and resolution for the span
SEARCH_LO, SEARCH_HI, SEARCH_POINTS = 15.0, 250.0, 256
# The span runs between these shares of the recent bass energy, and is never narrower than MIN_SPAN Hz
SPAN_FROM, SPAN_TO, MIN_SPAN = 0.01, 0.65, 50.0
# How long the energy profile behind the span and the per-point averages remembers, in seconds
MEMORY_SECONDS = 8.0
# Slow automatic gain: the loudest recent peak maps to 1, quiet parts fall back to it over ~20 s
DECAY = 0.9995
# Below this the room is treated as silent instead of being amplified into noise
FLOOR = 0.002
# Above 1 the scale expands: the bulk of the ring stays near the disc and peaks stand out
POWER = 2.0
# Each point is divided by its own average level, to this power: evens out the circle a little
# while a kick that always sits on one note still towers over the rest
WHITEN = 0.2
# Power averaged over this many frames before anything else: steadies the bins without delaying hits much
AVERAGE = 8
# Gaussian blur along the spectrum, in points, before anything is expanded: merges close harmonics
# into one smooth lobe instead of a bunch of needles
SMOOTH = 3.5
# Narrows the lobes: each point is scaled by (itself / the highest point within SHARP_REACH)^SHARP,
# so a peak keeps its height while its shoulders and the rest of the ring sink towards the disc
SHARP_REACH, SHARP = 8, 1.0
# Instant rise, eased fall: kills the frame-to-frame shimmer without blunting hits
RELEASE = 0.85
# Ear width is normalised per track: the leading lobe's half-height width is steered towards this
# many degrees of the half ring by raising the spectrum to a slowly adapting power. A smeared bass
# gets a higher power and narrows, a pure 808 needle gets one below 1 and widens
EAR_DEG, EAR_POW_RANGE, EAR_ADAPT = 34.0, (0.45, 4.0), 0.03
# Final light rounding along the spectrum, in points, so no lobe ends in a point
ROUND = 2.0
# Lobes past the leading one: 0 keeps them all, otherwise each lobe after the first is scaled by
# REST, and the second one by SECOND only once it reaches SECOND_FROM of the first's height
LEAD, SECOND, SECOND_FROM, REST = 0, 1.0, 0.0, 1.0
# Ears that travel: the span slides along the spectrum by up to this share of its width, on a slow
# swing that speeds up with the bass, so a note held in place still moves its ears around the ring
DRIFT = 0.0

# Variants picked live by a line on stdin, so the ring can be compared without a restart.
# One spectrum lobe is a pair of ears, the ring is mirrored
VARIANTS = {
    "classic": {},
    "lead": dict(LEAD=1, SECOND=0.0, SECOND_FROM=1.0, REST=0.2),
    "duet": dict(LEAD=1, SECOND=1.0, SECOND_FROM=0.55, REST=0.2),
    "wide": dict(SMOOTH=6.0, SHARP_REACH=20, SHARP=2.0),
    "calm": dict(LEAD=1, SECOND=1.0, SECOND_FROM=0.6, REST=0.25, AVERAGE=14, RELEASE=0.93, SMOOTH=5.0),
    "drift": dict(LEAD=1, SECOND=1.0, SECOND_FROM=0.55, REST=0.2, DRIFT=0.22),
    "kick": dict(LEAD=1, SECOND=1.0, SECOND_FROM=0.6, REST=0.15, WHITEN=0.0, POWER=3.0, RELEASE=0.8),
}
DEFAULTS = {k: globals()[k] for k in ("AVERAGE", "SMOOTH", "SHARP_REACH", "SHARP", "RELEASE", "WHITEN", "POWER",
                                      "LEAD", "SECOND", "SECOND_FROM", "REST", "DRIFT")}


def apply_variant(name):
    globals().update(DEFAULTS)
    globals().update(VARIANTS.get(name, {}))


def lobe_mask(v):
    # Each point belongs to the lobe it climbs to; lobes are ranked by height
    n = len(v)
    pad = np.concatenate([[-1.0], v, [-1.0]])
    idx = np.arange(n)
    climb = idx - 1 + np.argmax(np.stack([pad[:-2], pad[1:-1], pad[2:]]), axis=0)
    climb = np.where(v[np.clip(climb, 0, n - 1)] > v, climb, idx)
    owner = idx
    for _ in range(n):
        nxt = climb[owner]
        if (nxt == owner).all():
            break
        owner = nxt
    peaks = sorted(set(owner.tolist()), key=lambda p: -v[p])
    weight = {p: REST for p in peaks}
    weight[peaks[0]] = 1.0
    if len(peaks) > 1:
        r = v[peaks[1]] / max(v[peaks[0]], 1e-6)
        if r >= SECOND_FROM:
            weight[peaks[1]] = REST + (SECOND - REST) * min(1.0, (r - SECOND_FROM) / max(1e-6, 1 - SECOND_FROM) * 3)
    return np.array([weight[o] for o in owner])


def main():
    if len(sys.argv) > 1:
        src = open(sys.argv[1], "rb")
    else:
        src = subprocess.Popen(
            ["pw-record", "--raw", "-P", "{ stream.capture.sink=true node.name=nation-fft }", "--latency", "10ms",
             "--format", "s16", "--rate", str(RATE), "--channels", "1", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout

    sizes = [int(RATE * ms / 1000) for ms in WINDOWS_MS]
    # Hann windows normalised to unit sum, so a tone reads the same in every window length
    wins = [np.hanning(n) / np.hanning(n).sum() for n in sizes]
    freqs = np.fft.rfftfreq(NFFT, 1 / RATE)
    hi_bin = int(np.searchsorted(freqs, SEARCH_HI)) + 2
    grid = np.linspace(SEARCH_LO, SEARCH_HI, SEARCH_POINTS)
    follow = 1 / (MEMORY_SECONDS * FPS)
    buf = np.zeros(max(sizes), np.float32)
    recent = [[] for _ in sizes]
    energy = None
    peak = FLOOR
    shown = [np.zeros(POINTS) for _ in sizes]
    frame = 0
    out = sys.stdout
    half_r = int(ROUND * 3)
    round_k = np.exp(-0.5 * (np.arange(-half_r, half_r + 1) / ROUND) ** 2)
    round_k /= round_k.sum()
    ear_pow = 1.0
    mask = np.ones(POINTS)
    swing = 0.0
    apply_variant("classic")

    while True:
        if select.select([sys.stdin], [], [], 0)[0]:
            line = sys.stdin.readline()
            if not line:
                sys.stdin = open(os.devnull)
            else:
                apply_variant(line.strip())
                recent = [r[-AVERAGE:] for r in recent]
        chunk = src.read(HOP * 2)
        if len(chunk) < HOP * 2:
            break
        buf[:-HOP] = buf[HOP:]
        buf[-HOP:] = np.frombuffer(chunk, np.int16).astype(np.float32) / 32768

        # Power per layer, averaged over the last few frames
        layers = []
        for k, (n, w) in enumerate(zip(sizes, wins)):
            mag = np.abs(np.fft.rfft(buf[-n:] * w, NFFT)[:hi_bin])
            recent[k] = (recent[k] + [np.interp(grid, freqs[:hi_bin], mag) ** 2])[-AVERAGE:]
            layers.append(sum(recent[k]) / len(recent[k]))

        # Averages and the ease-in restart after silence (track start, pause)
        if np.sqrt(layers[0].max()) < FLOOR:
            energy, frame = None, 0
        energy = layers[0].copy() if energy is None else energy * (1 - follow) + layers[0] * follow
        cum = np.cumsum(energy)
        if cum[-1] > 0:
            cum /= cum[-1]
            lo = float(np.interp(SPAN_FROM, cum, grid))
            hi = max(float(np.interp(SPAN_TO, cum, grid)), lo + MIN_SPAN)
        else:
            lo, hi = 15.0, 110.0
        if DRIFT:
            # Two incommensurate sines, so the travel never settles into an obvious back and forth
            bass = min(1.0, float(np.sqrt(layers[0].max())) / peak) if peak > FLOOR else 0.0
            swing += (0.35 + 2.2 * bass * bass) / FPS
            shift = DRIFT * (hi - lo) * (0.65 * np.sin(swing) + 0.35 * np.sin(swing * 2.31 + 1.0))
            lo, hi = max(SEARCH_LO, lo + shift), max(SEARCH_LO + MIN_SPAN, hi + shift)
        targets = np.linspace(lo, hi, POINTS)
        level = np.sqrt(np.interp(targets, grid, energy))
        # Floor keeps silent bins from being blown up into noise
        norm = np.maximum(level, level.max() * 0.05 + 1e-9) ** WHITEN
        layers = [np.sqrt(np.interp(targets, grid, e)) / norm for e in layers]
        if SMOOTH > 0:
            half = int(SMOOTH * 3)
            kern = np.exp(-0.5 * (np.arange(-half, half + 1) / SMOOTH) ** 2)
            kern /= kern.sum()
            layers = [np.convolve(np.concatenate([m[half:0:-1], m, m[-2:-half - 2:-1]]), kern, "valid") for m in layers]

        peak = max(peak * DECAY, layers[0].max(), FLOOR)
        # The gain and the averages know nothing for the first moments: ease in instead of a blob
        frame += 1
        ramp = min(1, frame / (FPS * 0.75)) ** 2
        lines = []
        # Leading lobe width of the white ring as drawn last frame, in degrees, steers the shared power
        white = shown[0]
        top = int(white.argmax())
        if white[top] > 0.08:
            half = white[top] / 2
            lo_i, hi_i = top, top
            while lo_i > 0 and white[lo_i - 1] > half:
                lo_i -= 1
            while hi_i < POINTS - 1 and white[hi_i + 1] > half:
                hi_i += 1
            # A lobe on the seam is mirrored into one ear twice as wide
            span_pts = (hi_i - lo_i + 1) * (2 if lo_i == 0 or hi_i == POINTS - 1 else 1)
            deg = span_pts * 180 / (POINTS - 1)
            ear_pow = float(np.clip(ear_pow * np.exp(EAR_ADAPT * np.log(deg / EAR_DEG)), *EAR_POW_RANGE))
        if LEAD:
            # Eased so lobes swapping rank cross-fade instead of popping
            target = lobe_mask(np.clip(layers[0] / peak, 0, 1))
            mask = np.where(target > mask, mask * 0.7 + target * 0.3, mask * 0.85 + target * 0.15)
        else:
            mask[:] = 1
        for k, mag in enumerate(layers):
            v = np.clip(mag / peak, 0, 1) ** POWER * ramp * mask
            padded = np.concatenate([v[SHARP_REACH:0:-1], v, v[-2:-SHARP_REACH - 2:-1]])
            near = np.lib.stride_tricks.sliding_window_view(padded, 2 * SHARP_REACH + 1).max(axis=1)
            v = v * (v / np.maximum(near, 1e-6)) ** SHARP
            # Normalised width, then rounded. Mirrored padding, as the ring mirrors the spectrum at the top
            # and bottom: the slope there ends flat, so a lobe on the seam is round, not a beak
            top_v = max(float(v.max()), 1e-6)
            v = (v / top_v) ** ear_pow * top_v
            v = np.convolve(np.pad(v, half_r, mode="reflect"), round_k, "valid")
            prev = shown[k]
            v = np.where(v > prev, v, prev * RELEASE + v * (1 - RELEASE))
            shown[k] = v
            lines.append(";".join(str(int(x * 1000)) for x in v))
        out.write("|".join(lines) + "\n")
        out.flush()


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
