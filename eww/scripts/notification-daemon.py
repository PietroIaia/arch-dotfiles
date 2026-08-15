#!/usr/bin/python3.14
import json
import textwrap
import threading
import subprocess
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib, Gtk

IFACE = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"

NUM_SLOTS = 5
EMPTY_SLOT = "{}"
TOP_OFFSET = 5
SLOT_GAP = 8

# Per-line / per-block height contributions, in pixels. Tuned to the current SCSS
# (notification-app 11px bold, notification-title 13px bold, notification-body 12px,
# 4px margin-top between labels, 15px card padding, 2px border).
APP_ROW_H = 22       # app-name row including dismiss button vertical padding
SUMMARY_LINE_H = 20  # one line of summary
BODY_LINE_H = 18     # one line of body
BODY_TOP_MARGIN = 8  # space above the body block
ICON_H = 48
PAD_BORDER = 34      # 15px top + 15px bottom padding + 2px top + 2px bottom border

# GTK's auto-wrap is unreliable in this eww version, so the daemon hard-wraps text
# at fixed char counts before pushing it into slot vars. The text column is wider
# when there's no icon, so we wrap at different widths per case. Numbers assume
# ~6.5px average glyph width at 12px body font and ~7.5px at 13px summary font.
SUMMARY_WRAP_CHARS_WITH_ICON = 33
SUMMARY_WRAP_CHARS_NO_ICON = 41
BODY_WRAP_CHARS_WITH_ICON = 40
BODY_WRAP_CHARS_NO_ICON = 50


class NotificationDaemon(dbus.service.Object):
    def __init__(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SessionBus()
        bus_name = dbus.service.BusName(IFACE, bus)
        super().__init__(bus_name, PATH)
        self._notifications: dict[int, dict] = {}
        self._timers: dict[int, threading.Timer] = {}
        self._next_id = 1
        # _slots is compacted: occupied entries pack toward index 0.
        self._slots: list[int | None] = [None] * NUM_SLOTS
        self._slot_open: list[bool] = [False] * NUM_SLOTS
        self._slot_geom: dict[int, tuple[int, int]] = {}  # idx -> (y, h)
        self._queue: list[int] = []
        self._lock = threading.Lock()
        # Ensure clean state on startup (eww may have stale windows from a previous run).
        for i in range(NUM_SLOTS):
            self._close_window(i)
        self._start_periodic_reemit()

    # --- screen / window plumbing ---

    def _target_screen(self) -> str | None:
        try:
            result = subprocess.run(
                ["hyprctl", "monitors", "-j"],
                capture_output=True, text=True, timeout=2,
            )
            monitors = json.loads(result.stdout)
            for i, mon in enumerate(monitors):
                if mon.get("name") == "HDMI-A-1":
                    return str(i)
            for i, mon in enumerate(monitors):
                if mon.get("name") == "eDP-1":
                    return str(i)
            if monitors:
                return "0"
        except Exception:
            return None
        return None

    @staticmethod
    def _eww_update(var: str, value: str):
        subprocess.run(
            ["eww", "update", f"{var}={value}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def _open_window(self, idx: int, y: int, h: int, width: int = 360):
        cmd = [
            "eww", "open", f"notif-slot-{idx}",
            "--pos", f"5x{y}",
            "--size", f"{width}x{h}",
            "--anchor", "top right",
        ]
        screen = self._target_screen()
        if screen is not None:
            cmd.extend(["--screen", screen])
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self._slot_open[idx] = True

    def _close_window(self, idx: int):
        subprocess.run(
            ["eww", "close", f"notif-slot-{idx}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self._eww_update(f"slot_{idx}", EMPTY_SLOT)
        self._slot_open[idx] = False
        self._slot_geom.pop(idx, None)

    # --- text wrapping and height estimation ---

    @staticmethod
    def _wrap(text: str, width: int) -> str:
        if not text:
            return ""
        out_lines: list[str] = []
        for paragraph in text.split("\n"):
            if not paragraph:
                out_lines.append("")
                continue
            wrapped = textwrap.wrap(
                paragraph, width=width,
                break_long_words=True, break_on_hyphens=False,
                replace_whitespace=False, drop_whitespace=False,
            )
            out_lines.extend(wrapped or [""])
        return "\n".join(out_lines)

    @staticmethod
    def _estimate_height(n: dict) -> int:
        summary = n.get("summary") or ""
        body = n.get("body") or ""
        summary_lines = summary.count("\n") + 1 if summary else 1
        body_lines = (body.count("\n") + 1) if body else 0
        text_h = APP_ROW_H + summary_lines * SUMMARY_LINE_H
        if body_lines:
            text_h += BODY_TOP_MARGIN + body_lines * BODY_LINE_H
        icon_h = ICON_H if n.get("icon") else 0
        return max(text_h, icon_h) + PAD_BORDER

    # --- slot bookkeeping (compacted toward index 0) ---

    def _slot_of(self, nid: int) -> int | None:
        for i, occupant in enumerate(self._slots):
            if occupant == nid:
                return i
        return None

    def _first_free_slot(self) -> int | None:
        for i, occupant in enumerate(self._slots):
            if occupant is None:
                return i
        return None

    def _compact_after(self, removed_idx: int):
        for i in range(removed_idx, NUM_SLOTS - 1):
            self._slots[i] = self._slots[i + 1]
        self._slots[NUM_SLOTS - 1] = None

    def _place(self, nid: int):
        if self._slot_of(nid) is not None:
            self._relayout()
            return
        idx = self._first_free_slot()
        if idx is None:
            if nid not in self._queue:
                self._queue.append(nid)
            return
        self._slots[idx] = nid
        self._relayout()

    def _release(self, nid: int):
        if nid in self._queue:
            self._queue.remove(nid)
        idx = self._slot_of(nid)
        if idx is None:
            return
        self._slots[idx] = None
        self._compact_after(idx)
        while self._queue:
            next_nid = self._queue.pop(0)
            if next_nid in self._notifications:
                free = self._first_free_slot()
                if free is None:
                    break
                self._slots[free] = next_nid
                break
        self._relayout()

    # --- layout pass ---

    def _relayout(self):
        cur_y = TOP_OFFSET
        for i in range(NUM_SLOTS):
            nid = self._slots[i]
            if nid is None or nid not in self._notifications:
                if self._slot_open[i]:
                    self._close_window(i)
                continue
            n = self._notifications[nid]
            h = self._estimate_height(n)
            y = cur_y
            cur_y += h + SLOT_GAP
            self._eww_update(f"slot_{i}", json.dumps(n))
            geom = (y, h)
            if self._slot_geom.get(i) != geom or not self._slot_open[i]:
                if self._slot_open[i]:
                    subprocess.run(
                        ["eww", "close", f"notif-slot-{i}"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    self._slot_open[i] = False
                self._open_window(i, y, h)
                self._slot_geom[i] = geom

    # --- self-heal ---

    def _start_periodic_reemit(self):
        t = threading.Timer(30.0, self._periodic_tick)
        t.daemon = True
        t.start()

    def _periodic_tick(self):
        with self._lock:
            self._relayout()
        self._start_periodic_reemit()

    # --- D-Bus ---

    @dbus.service.method(IFACE, in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout):
        with self._lock:
            nid = int(replaces_id) if int(replaces_id) > 0 else self._next_id
            self._next_id = max(self._next_id + 1, nid + 1)

            urgency_raw = hints.get("urgency", dbus.Byte(1))
            urgency = ["low", "normal", "critical"][min(int(urgency_raw), 2)]

            if nid in self._timers:
                self._timers[nid].cancel()
                del self._timers[nid]

            icon = self._resolve_icon(str(app_icon))
            summary_chars = SUMMARY_WRAP_CHARS_WITH_ICON if icon else SUMMARY_WRAP_CHARS_NO_ICON
            body_chars = BODY_WRAP_CHARS_WITH_ICON if icon else BODY_WRAP_CHARS_NO_ICON
            self._notifications[nid] = {
                "id": nid,
                "app_name": str(app_name),
                "summary": self._wrap(str(summary), summary_chars),
                "body": self._wrap(str(body), body_chars),
                "urgency": urgency,
                "icon": icon,
            }

            self._place(nid)
            self._play_sound(urgency)
            self._schedule_timeout(nid, urgency, int(expire_timeout))
            return dbus.UInt32(nid)

    def _resolve_icon(self, app_icon: str) -> str:
        if not app_icon:
            return ""
        if app_icon.startswith("/"):
            return app_icon
        icon_theme = Gtk.IconTheme.get_default()
        icon_info = icon_theme.lookup_icon(app_icon, 48, 0)
        if icon_info:
            return icon_info.get_filename() or ""
        return ""

    def _play_sound(self, urgency: str):
        sounds = {
            "low":      "/usr/share/sounds/freedesktop/stereo/dialog-error.oga",
            "normal":   "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
            "critical": "/usr/share/sounds/freedesktop/stereo/message.oga",
        }
        path = sounds.get(urgency)
        if path:
            subprocess.Popen(
                ["paplay", "--volume=98304", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

    def _schedule_timeout(self, nid: int, urgency: str, expire_timeout: int):
        if urgency == "critical":
            return
        ms = expire_timeout if expire_timeout > 0 else 5000
        t = threading.Timer(ms / 1000, self._expire, args=[nid])
        self._timers[nid] = t
        t.start()

    def _expire(self, nid: int):
        self.CloseNotification(dbus.UInt32(nid))

    @dbus.service.method(IFACE, in_signature="u", out_signature="")
    def CloseNotification(self, nid):
        with self._lock:
            nid = int(nid)
            if nid in self._timers:
                self._timers[nid].cancel()
                del self._timers[nid]
            if nid in self._notifications:
                del self._notifications[nid]
                self._release(nid)
            self.NotificationClosed(dbus.UInt32(nid), dbus.UInt32(2))

    @dbus.service.signal(IFACE, signature="uu")
    def NotificationClosed(self, nid, reason):
        pass

    @dbus.service.method(IFACE, in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ["body", "body-markup", "persistence"]

    @dbus.service.method(IFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("eww-notifications", "eww-dotfiles", "1.0", "1.2")


if __name__ == "__main__":
    daemon = NotificationDaemon()
    GLib.MainLoop().run()
