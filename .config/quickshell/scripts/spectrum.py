#!/usr/bin/env python3
# Spectrum analysers for the desk visualizers, an alternative to cava's bands.
# Prints one line per frame at 60 fps: BANDS values 0..1000 split by ";", bass first.
# Modes:
#   pro    log 30 Hz-16 kHz, dB scale against a slow auto gain, tilted +3 dB/oct like a studio analyser
#   vocal  mel scale 80 Hz-8 kHz: the voice and leads take most of the width
#   punch  spectral flux: only what just got louder lights up, so hits jump and sustains fade
#   fluid  pro, heavily blurred across bands and eased in time: one slow rolling landscape
#   sub    linear 20-200 Hz over a long window: kicks and 808 notes as separate humps
# Usage: spectrum.py MODE [RAW_S16_MONO_48K_FILE]   (no file: capture what the speakers play)

import subprocess
import sys

import numpy as np

RATE = 48000
FPS = 60
HOP = RATE // FPS
BANDS = 48

MODES = {
    # window ms, edges, scale, attack, release, blur in bands
    "pro": dict(win=80, lo=30, hi=16000, scale="log", release=0.82, blur=0.8, tilt=3.0),
    "vocal": dict(win=60, lo=80, hi=8000, scale="mel", release=0.8, blur=1.0, tilt=1.5),
    "punch": dict(win=40, lo=30, hi=12000, scale="log", release=0.7, blur=0.8, tilt=2.0),
    "fluid": dict(win=100, lo=30, hi=12000, scale="log", release=0.93, blur=2.5, tilt=3.0),
    "sub": dict(win=250, lo=20, hi=200, scale="lin", release=0.85, blur=1.2, tilt=0.0),
}
# dB shown below the running peak; the auto gain forgets a loud peak over ~20 s
RANGE_DB = 45.0
DECAY_DB = 0.004
FLOOR_DB = -75.0


def edges(cfg):
    lo, hi = cfg["lo"], cfg["hi"]
    n = BANDS + 1
    if cfg["scale"] == "lin":
        return np.linspace(lo, hi, n)
    if cfg["scale"] == "mel":
        m = lambda f: 2595 * np.log10(1 + f / 700)
        return 700 * (10 ** (np.linspace(m(lo), m(hi), n) / 2595) - 1)
    return np.geomspace(lo, hi, n)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in MODES else "pro"
    cfg = MODES[mode]
    if len(sys.argv) > 2:
        src = open(sys.argv[2], "rb")
    else:
        src = subprocess.Popen(
            ["pw-record", "--raw", "-P", f"{{ stream.capture.sink=true node.name=spectrum-{mode} }}", "--latency", "10ms",
             "--format", "s16", "--rate", str(RATE), "--channels", "1", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout

    size = int(RATE * cfg["win"] / 1000)
    nfft = 1 << int(np.ceil(np.log2(max(size, 4096))))
    if mode == "sub":
        nfft = 1 << 15
    win = np.hanning(size)
    win /= win.sum()
    freqs = np.fft.rfftfreq(nfft, 1 / RATE)
    e = edges(cfg)
    # Each band is the power mean of its bins; narrow low bands that hold no bin read the nearest one
    lo_bin = np.searchsorted(freqs, e[:-1])
    hi_bin = np.maximum(lo_bin + 1, np.searchsorted(freqs, e[1:]))
    centres = np.sqrt(e[:-1] * e[1:]) if cfg["scale"] != "lin" else (e[:-1] + e[1:]) / 2
    tilt = cfg["tilt"] * np.log2(centres / 1000)
    blur = cfg["blur"]
    half = max(1, int(blur * 3))
    kern = np.exp(-0.5 * (np.arange(-half, half + 1) / blur) ** 2)
    kern /= kern.sum()

    buf = np.zeros(size, np.float32)
    peak = FLOOR_DB + RANGE_DB
    prev_db = np.full(BANDS, FLOOR_DB)
    shown = np.zeros(BANDS)
    out = sys.stdout

    while True:
        chunk = src.read(HOP * 2)
        if len(chunk) < HOP * 2:
            break
        buf[:-HOP] = buf[HOP:]
        buf[-HOP:] = np.frombuffer(chunk, np.int16).astype(np.float32) / 32768

        power = np.abs(np.fft.rfft(buf * win, nfft)) ** 2
        cum = np.concatenate([[0], np.cumsum(power)])
        band = (cum[hi_bin] - cum[lo_bin]) / (hi_bin - lo_bin)
        db = 10 * np.log10(band + 1e-14) + tilt
        db = np.convolve(np.concatenate([db[half:0:-1], db, db[-2:-half - 2:-1]]), kern, "valid")

        peak = max(peak - DECAY_DB * 60 / FPS, db.max(), FLOOR_DB + RANGE_DB)
        v = np.clip((db - (peak - RANGE_DB)) / RANGE_DB, 0, 1) ** 1.6
        if mode == "punch":
            # Rise over the recent level, in dB, weighted by loudness so quiet bands can't flicker
            flux = np.maximum(0, db - prev_db)
            prev_db = prev_db * 0.85 + db * 0.15
            v = np.clip(flux / 12, 0, 1) * np.sqrt(v)

        # Instant rise, eased fall
        rel = cfg["release"]
        shown = np.where(v > shown, v if mode != "fluid" else shown * 0.6 + v * 0.4, shown * rel + v * (1 - rel))
        out.write(";".join(str(int(x * 1000)) for x in shown) + "\n")
        out.flush()


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
