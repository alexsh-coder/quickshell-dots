#!/usr/bin/env python3
"""Runs a command with transparent huge pages off for it and its children.

With THP on "always", the shell's many small heaps get backed by 2 MB pages and its memory roughly doubles."""
import ctypes
import os
import sys

PR_SET_THP_DISABLE = 41
ctypes.CDLL(None).prctl(PR_SET_THP_DISABLE, 1, 0, 0, 0)
os.execvp(sys.argv[1], sys.argv[1:])
