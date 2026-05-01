#!/usr/bin/python3.14
import json
import threading
import subprocess
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib, Gtk

IFACE = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"


class NotificationDaemon(dbus.service.Object):
    def __init__(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SessionBus()
        bus_name = dbus.service.BusName(IFACE, bus)
        super().__init__(bus_name, PATH)
        self._notifications: dict[int, dict] = {}
        self._timers: dict[int, threading.Timer] = {}
        self._next_id = 1

    def _emit(self):
        print(json.dumps(list(self._notifications.values())), flush=True)

    @dbus.service.method(IFACE, in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout):
        nid = int(replaces_id) if int(replaces_id) > 0 else self._next_id
        self._next_id = max(self._next_id + 1, nid + 1)

        urgency_raw = hints.get("urgency", dbus.Byte(1))
        urgency = ["low", "normal", "critical"][min(int(urgency_raw), 2)]

        if nid in self._timers:
            self._timers[nid].cancel()
            del self._timers[nid]

        self._notifications[nid] = {
            "id": nid,
            "app_name": str(app_name),
            "summary": str(summary),
            "body": str(body),
            "urgency": urgency,
            "icon": self._resolve_icon(str(app_icon)),
        }

        self._emit()
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
        nid = int(nid)
        if nid in self._timers:
            self._timers[nid].cancel()
            del self._timers[nid]
        if nid in self._notifications:
            del self._notifications[nid]
            self._emit()
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
    print("[]", flush=True)
    GLib.MainLoop().run()
