#!/usr/bin/env python3
"""Tint the mouse pointer while Caps Lock is on.

Mirrors the Neovim cursor tint in ~/.config/nvim/lua/config/capslock.lua: on a
Caps Lock change the whole cursor theme is swapped, which repaints Hyprland's
own pointer and — with cursor:sync_gsettings_theme enabled — pushes the theme
to GTK apps too.  The tinted theme is built by gen-capslock-cursors.py.

Caps Lock state comes from the keyboard LEDs in sysfs; several devices may
expose one and any of them being lit counts.  The LED class has no
brightness_hw_changed attribute and does not sysfs_notify, so there is nothing
to poll() on and the state has to be sampled on a timer.  Holding the fds open
and pread()ing them keeps a sample at ~3us, cheap enough to run at 10ms; the
remaining latency is Hyprland rasterising the theme (~20ms).
"""

import glob
import os
import socket
import sys
import time

THEME_ON = "Adwaita-CapsLock"
THEME_OFF = "Adwaita"
SIZE = os.environ.get("XCURSOR_SIZE", "24")
INTERVAL = 0.01

leds = [os.open(p, os.O_RDONLY) for p in glob.glob("/sys/class/leds/*capslock*/brightness")]
if not leds:
    sys.exit(0)

runtime = os.environ.get("XDG_RUNTIME_DIR", "")
signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
if not runtime or not signature:
    sys.exit("not running under Hyprland")
SOCKET = os.path.join(runtime, "hypr", signature, ".socket.sock")


def caps_on():
    return any(os.pread(fd, 4, 0).strip() not in (b"", b"0") for fd in leds)


def set_cursor(theme):
    """Ask Hyprland for a cursor theme over its IPC socket.

    Cheaper than shelling out to hyprctl, and a failure here (compositor gone
    or restarting) should not take the daemon down — the next toggle retries.
    """
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(SOCKET)
            sock.sendall(f"/setcursor {theme} {SIZE}".encode())
            sock.recv(64)
    except OSError:
        pass


state = None
while True:
    on = caps_on()
    if on is not state:
        state = on
        set_cursor(THEME_ON if on else THEME_OFF)
    time.sleep(INTERVAL)
