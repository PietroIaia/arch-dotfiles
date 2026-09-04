#!/usr/bin/env python3
"""Build the Caps Lock variant of the Adwaita cursor theme.

Adwaita's pointers are a black fill inside a white outline, sitting on a
semi-transparent black drop shadow.  This remaps the *opaque* pixels so black
becomes TINT and white stays white (greys interpolate, which keeps the
antialiasing clean); the shadow is left alone so it stays a shadow.

Xcursor files are patched in place: only the ARGB payload of each image chunk
is rewritten, so the header/table of contents never has to be rebuilt.

Re-run after an adwaita-cursors upgrade:
    ~/.config/hypr/scripts/gen-capslock-cursors.py
"""

import os
import shutil
import struct
import sys

SRC = "/usr/share/icons/Adwaita"
DST = os.path.expanduser("~/.local/share/icons/Adwaita-CapsLock")
TINT = (0xBE, 0x87, 0xFF)  # keep in sync with ~/.config/nvim/lua/config/capslock.lua

CHUNK_IMAGE = 0xFFFD0002
# Below FADE_LO a pixel is drop shadow and is left untouched; above FADE_HI it is
# solid cursor body and is fully recoloured.  In between the two are crossfaded.
FADE_LO, FADE_HI = 153, 230


def recolour(pixel):
    """Recolour one premultiplied-ARGB pixel."""
    a = pixel >> 24
    if a < FADE_LO:
        return pixel
    b, g, r = pixel & 0xFF, (pixel >> 8) & 0xFF, (pixel >> 16) & 0xFF
    # Undo premultiplication so the tint maths sees the real colour.
    ur, ug, ub = (min(255, c * 255 // a) for c in (r, g, b))
    lum = (0.2126 * ur + 0.7152 * ug + 0.0722 * ub) / 255  # 0 = fill, 1 = outline
    t = min(1.0, (a - FADE_LO) / (FADE_HI - FADE_LO))

    out = []
    for orig, tint in zip((ur, ug, ub), TINT):
        new = tint + (255 - tint) * lum  # black -> TINT, white -> white
        blended = orig + (new - orig) * t
        out.append(round(blended * a / 255))  # premultiply again
    nr, ng, nb = (max(0, min(a, c)) for c in out)
    return (a << 24) | (nr << 16) | (ng << 8) | nb


def patch(path):
    data = bytearray(open(path, "rb").read())
    magic, header, _version, ntoc = struct.unpack_from("<4sIII", data, 0)
    if magic != b"Xcur":
        raise ValueError(f"{path}: not an Xcursor file")

    for i in range(ntoc):
        chunk_type, _subtype, pos = struct.unpack_from("<III", data, header + i * 12)
        if chunk_type != CHUNK_IMAGE:
            continue
        chunk_header, _t, _s, _v, w, h, _xh, _yh, _delay = struct.unpack_from(
            "<9I", data, pos
        )
        start = pos + chunk_header
        for n in range(w * h):
            off = start + n * 4
            (pixel,) = struct.unpack_from("<I", data, off)
            struct.pack_into("<I", data, off, recolour(pixel))

    open(path, "wb").write(data)


def main():
    src_cursors = os.path.join(SRC, "cursors")
    if not os.path.isdir(src_cursors):
        sys.exit(f"{src_cursors} not found — is adwaita-cursors installed?")

    dst_cursors = os.path.join(DST, "cursors")
    shutil.rmtree(DST, ignore_errors=True)
    os.makedirs(dst_cursors)

    with open(os.path.join(DST, "index.theme"), "w") as fd:
        fd.write(
            "[Icon Theme]\n"
            "Name=Adwaita-CapsLock\n"
            "Comment=Adwaita cursors tinted while Caps Lock is on\n"
            "Inherits=Adwaita\n"
            "Hidden=true\n"
        )

    links = patched = 0
    for name in sorted(os.listdir(src_cursors)):
        src = os.path.join(src_cursors, name)
        dst = os.path.join(dst_cursors, name)
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)  # aliases stay aliases
            links += 1
        else:
            shutil.copyfile(src, dst)
            patch(dst)
            patched += 1

    print(f"{DST}: {patched} cursors tinted #{'%02x%02x%02x' % TINT}, {links} aliases")


if __name__ == "__main__":
    main()
