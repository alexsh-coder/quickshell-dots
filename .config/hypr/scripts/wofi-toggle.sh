#!/usr/bin/env bash
# Launch wofi only if no instance is already running, so it can't be opened over itself.
pgrep -x wofi >/dev/null || wofi --show drun
