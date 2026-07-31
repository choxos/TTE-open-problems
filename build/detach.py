#!/usr/bin/env python3
"""Start a command in its own session so it survives the parent's process group being reaped.

macOS has no setsid(1). The long-running auditor driver kept dying whenever the shell that
launched it was cleaned up, taking half-finished batches with it.

Usage: detach.py <logfile> <command> [args...]
"""
import os
import sys

log = sys.argv[1]
cmd = sys.argv[2:]

if os.fork() != 0:
    sys.exit(0)          # parent returns immediately

os.setsid()              # new session: no longer in the caller's process group

if os.fork() != 0:
    os._exit(0)          # intermediate exits so the child cannot reacquire a terminal

fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.dup2(fd, 1)
os.dup2(fd, 2)
os.close(os.open(os.devnull, os.O_RDONLY))
os.execvp(cmd[0], cmd)
