#!/usr/bin/python3.14
# Emits the MPRIS player shown in the bar's now-playing island as one JSON line per change.
import json
import os
import re
import sys
import time
from dataclasses import dataclass

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

sys.dont_write_bytecode = True  # keep lib/__pycache__ out of the config repo
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from anim import ANIM_MS, FRAME_MS, ease  # noqa: E402

MPRIS_PREFIX = "org.mpris.MediaPlayer2."
MPRIS_PATH = "/org/mpris/MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
CALL_TIMEOUT = 1.0
BROWSERS = ("vivaldi", "chromium", "chrome", "brave", "firefox")
TEXT_CHARS = 100  # widest bar; narrower bars slice it in yuck
GAP = " " * 60
TICK_MS = 250
HOLD_TICKS = 1  # first move after (HOLD_TICKS + 1) ticks: 500ms on a new track or resume
REVEAL_FULL = 1000  # reveal is in permille so yuck can scale any bar's width with integers
HIDDEN: dict[str, str | bool | int] = {
    "visible": False, "status": "", "title": "", "artist": "", "source": "", "text_view": "", "reveal": 0,
}


@dataclass
class Player:
    name: str
    status: str = ""
    title: str = ""
    artist: str = ""
    url: str = ""
    changed: int = 0  # tick of the last status/title change; latest wins in pick()


def clean(text: str) -> str:
    # eww blanks any label whose text holds a backslash.
    return re.sub(r"\s+", " ", text.replace("\\", "∖")).strip()


def source_of(p: Player) -> str:
    name = p.name.removeprefix(MPRIS_PREFIX).lower()
    if name.startswith("spotify"):
        return "spotify"
    if "youtube.com" in p.url or "youtu.be" in p.url:
        return "youtube"
    if any(b in name for b in BROWSERS):
        return "browser"
    return "generic"


def pick(players: dict[str, Player]) -> Player | None:
    eligible = [p for p in players.values() if p.status in ("Playing", "Paused") and p.title]
    pool = [p for p in eligible if p.status == "Playing"] or eligible
    return max(pool, key=lambda p: p.changed) if pool else None


def label_of(p: Player) -> str:
    return f"{p.title} · {p.artist}" if p.artist else p.title


def window(text: str, offset: int) -> str:
    loop = text + GAP
    return (loop * (TEXT_CHARS // len(loop) + 2))[offset:offset + TEXT_CHARS]


def render(p: Player | None, offset: int) -> dict[str, str | bool | int]:
    if p is None:
        return HIDDEN
    return {
        "visible": True,
        "status": p.status,
        "title": p.title,
        "artist": p.artist,
        "source": source_of(p),
        "text_view": window(label_of(p), offset),
        "reveal": REVEAL_FULL,
    }


@dataclass
class Marquee:
    offset: int = 0
    hold: int = HOLD_TICKS

    def advance(self, length: int) -> None:
        if self.hold:
            self.hold -= 1
        else:
            self.offset = (self.offset + 1) % length

    def reset(self) -> None:
        self.offset = 0
        self.hold = HOLD_TICKS


class Listener:
    def __init__(self, bus: dbus.SessionBus) -> None:
        self._bus = bus
        self._players: dict[str, Player] = {}  # keyed by unique owner, which signals carry as sender
        self._tick = 0
        self._last = ""
        self._marquee = Marquee()
        self._marquee_key = ""
        self._timer: int | None = None
        self._shown = HIDDEN  # last visible render; kept while the pill closes
        self._reveal = 0
        self._anim_from = 0
        self._anim_target = 0
        self._anim_t0 = 0.0
        self._anim_timer: int | None = None
        bus.add_signal_receiver(
            self._on_owner, signal_name="NameOwnerChanged",
            dbus_interface="org.freedesktop.DBus", bus_name="org.freedesktop.DBus",
            arg0namespace=MPRIS_PREFIX.rstrip("."),
        )
        bus.add_signal_receiver(
            self._on_props, signal_name="PropertiesChanged",
            dbus_interface=PROPS_IFACE, path=MPRIS_PATH, sender_keyword="sender",
        )
        for name in bus.list_names():
            if name.startswith(MPRIS_PREFIX):
                try:
                    self._add(str(name), str(bus.get_name_owner(name)))
                except dbus.DBusException:
                    pass
        self._emit()

    def _add(self, name: str, owner: str) -> None:
        # Kept even when GetAll fails, so its later PropertiesChanged still lands.
        self._players[owner] = Player(name)
        self._fetch(owner)

    def _fetch(self, owner: str) -> None:
        try:
            props = self._bus.get_object(owner, MPRIS_PATH, introspect=False).GetAll(
                PLAYER_IFACE, dbus_interface=PROPS_IFACE, timeout=CALL_TIMEOUT,
            )
        except dbus.DBusException:
            return
        self._merge(owner, props)

    def _merge(self, owner: str, props: dbus.Dictionary) -> None:
        p = self._players[owner]
        old = (p.status, p.title)
        if "PlaybackStatus" in props:
            p.status = str(props["PlaybackStatus"])
        if "Metadata" in props:
            meta = props["Metadata"]
            artist = meta.get("xesam:artist", [])
            artists = [artist] if isinstance(artist, str) else artist
            p.title = clean(str(meta.get("xesam:title", "")))
            p.artist = clean(", ".join(str(a) for a in artists))
            p.url = str(meta.get("xesam:url", ""))
        if (p.status, p.title) != old:
            self._tick += 1
            p.changed = self._tick

    def _on_owner(self, name: str, old: str, new: str) -> None:
        if not name.startswith(MPRIS_PREFIX):
            return
        self._players.pop(str(old), None)
        if new:
            self._add(str(name), str(new))
        self._emit()

    def _on_props(self, iface: str, changed: dbus.Dictionary, invalidated: dbus.Array, sender: str) -> None:
        if iface != PLAYER_IFACE or sender not in self._players:
            return
        self._merge(sender, changed)
        if "PlaybackStatus" in invalidated or "Metadata" in invalidated:
            self._fetch(sender)
        self._emit()

    def _sync_marquee(self, p: Player | None) -> None:
        key = f"{p.name}|{label_of(p)}|{p.status}" if p else ""
        if key != self._marquee_key:
            self._marquee_key = key
            self._marquee.reset()
        playing = p is not None and p.status == "Playing"
        if playing and self._timer is None:
            self._timer = GLib.timeout_add(TICK_MS, self._on_tick)
        elif not playing and self._timer is not None:
            GLib.source_remove(self._timer)
            self._timer = None

    def _on_tick(self) -> bool:
        p = pick(self._players)
        if p is None or p.status != "Playing":
            self._timer = None
            return False
        self._marquee.advance(len(label_of(p) + GAP))
        self._emit()
        return True

    def _sync_anim(self, p: Player | None) -> None:
        target = REVEAL_FULL if p else 0
        if target != self._anim_target:
            self._anim_from, self._anim_target, self._anim_t0 = self._reveal, target, time.monotonic()
            if self._anim_timer is None:
                self._anim_timer = GLib.timeout_add(FRAME_MS, self._on_frame)

    def _on_frame(self) -> bool:
        t = (time.monotonic() - self._anim_t0) * 1000 / ANIM_MS
        self._reveal = ease(self._anim_from, self._anim_target, t)
        done = t >= 1
        if done:
            self._anim_timer = None
        self._emit()
        return not done

    def _emit(self) -> None:
        p = pick(self._players)
        self._sync_marquee(p)
        self._sync_anim(p)
        if p:
            self._shown = render(p, self._marquee.offset)
        out = {**self._shown, "visible": self._reveal > 0, "reveal": self._reveal}
        line = json.dumps(out, ensure_ascii=False)
        if line != self._last:
            self._last = line
            try:
                print(line, flush=True)
            except BrokenPipeError:
                os._exit(0)  # eww is gone; don't linger on the bus


def main() -> int:
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SessionBus()
    except dbus.DBusException:
        print(json.dumps(HIDDEN), flush=True)
        return 0
    Listener(bus)
    # Exit once eww closes our stdout, even while idle and not writing.
    GLib.io_add_watch(
        sys.stdout.fileno(), GLib.PRIORITY_DEFAULT,
        GLib.IOCondition.ERR | GLib.IOCondition.HUP, lambda *_: os._exit(0),
    )
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
