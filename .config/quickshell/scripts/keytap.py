#!/usr/bin/env python3
# Prints one character per typing key press on any keyboard, for typing sounds:
# "e" for enter, "b" for space, backspace, delete and tab, "k" for the rest.
# Arrows, Esc, F-keys and shortcuts are not typing and stay quiet. Which key it was is never printed.
# Needs read access to /dev/input (the "input" group).
import os, re, select, struct, sys, time

EVENT = struct.Struct("llHHi")
ENTER = {28, 96}
BIG = {14, 15, 57, 111}  # backspace, tab, space, delete
# Letters, digits, punctuation and the keypad
TYPING = set(range(2, 14)) | set(range(16, 28)) | set(range(30, 42)) | set(range(43, 54)) | {55, 86, 98} | set(range(71, 84)) | ENTER | BIG
# Ctrl, Alt, Super: these and anything pressed with them are shortcuts, not typing
MODS = {29, 97, 56, 100, 125, 126}
held = set()


def keyboards():
    found = set()
    try:
        text = open("/proc/bus/input/devices").read()
    except OSError:
        return found
    for block in text.split("\n\n"):
        ev = re.search(r"B: EV=(\w+)", block)
        handlers = re.search(r"H: Handlers=(.*)", block)
        # Keys plus LEDs and repeat: a real keyboard, not a power button or a mouse
        if ev and handlers and int(ev.group(1), 16) & 0x120013 == 0x120013:
            for h in handlers.group(1).split():
                if h.startswith("event"):
                    found.add("/dev/input/" + h)
    return found


fds = {}
last_scan = 0
while True:
    if time.monotonic() - last_scan > 5:
        last_scan = time.monotonic()
        for path in keyboards() - set(fds.values()):
            try:
                fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
            except OSError:
                pass
    if not fds:
        time.sleep(5)
        continue
    ready, _, _ = select.select(list(fds), [], [], 5)
    for fd in ready:
        try:
            data = os.read(fd, EVENT.size * 64)
        except OSError:
            os.close(fd)
            del fds[fd]
            continue
        out = ""
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _, _, type_, code, value = EVENT.unpack_from(data, i)
            if type_ != 1:
                continue
            if code in MODS:
                if value:
                    held.add(code)
                else:
                    held.discard(code)
            elif value == 1 and not held and code in TYPING:
                out += "e" if code in ENTER else "b" if code in BIG else "k"
        if out:
            sys.stdout.write(out + "\n")
            sys.stdout.flush()
