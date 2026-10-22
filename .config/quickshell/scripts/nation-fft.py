#!/usr/bin/env python3
# Bass spectrum for the Nation ring, the way Trap Nation's After Effects template builds it:
# a linear bass spectrum (bent into a circle and mirrored by the QML side), taken over several
# window lengths. The longest window is the steady white ring, shorter ones react faster and
# become the coloured layers behind it.
# The frequency span follows the track: it covers the stretch of 15-250 Hz that holds most of the
# recent bass energy, so a sped-up track whose bass sits higher still fills the whole circle.
# Prints one line per frame at 60 fps: layers split by "|", points by ";", values 0..1000.
# Usage: nation-fft.py [RAW_S16_MONO_48K_FILE]   (no file: capture what the speakers play)

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


def main():
    if len(sys.argv) > 1:
        src = open(sys.argv[1], "rb")
    else:
        src = subprocess.Popen(
            ["pw-record", "-P", "{ stream.capture.sink=true node.name=nation-fft }", "--latency", "10ms",
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

    while True:
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
        for k, mag in enumerate(layers):
            v = np.clip(mag / peak, 0, 1) ** POWER * ramp
            padded = np.concatenate([v[SHARP_REACH:0:-1], v, v[-2:-SHARP_REACH - 2:-1]])
            near = np.lib.stride_tricks.sliding_window_view(padded, 2 * SHARP_REACH + 1).max(axis=1)
            v = v * (v / np.maximum(near, 1e-6)) ** SHARP
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
