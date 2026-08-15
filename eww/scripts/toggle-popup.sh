#!/bin/bash
# Usage: toggle-popup.sh <popup-name> <screen-index>
#
# eww SIGKILLs a widget's onclick command once it exceeds the widget :timeout
# (200ms by default). Every `eww` CLI call here is a ~25ms IPC round-trip to the
# daemon, and the calendar branch needs ~208ms of them — it was being killed
# just before `eww open` ran, leaving popup_open set but no window on screen.
# So re-exec detached and return immediately: the process eww supervises now
# exits in ~1ms and the timeout can never apply to any popup.
if [ "$1" != "--worker" ]; then
    setsid "$0" --worker "$@" </dev/null >/dev/null 2>&1 &
    exit 0
fi
shift

POPUP="$1"
SCREEN="$2"

# Drop overlapping clicks rather than queueing them, so a fast double-click
# can't open the popup and immediately close it again.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/eww-popup-toggle.lock"
flock -n 9 || exit 0

CURRENT=$(eww get popup_open)

if [ "$CURRENT" = "$POPUP" ]; then
    # Same popup clicked — toggle off
    eww update popup_open="none"
    eww close "$POPUP"
    eww close click-catcher-0 2>/dev/null
    eww close click-catcher-1 2>/dev/null
else
    # Different popup — close current if any, then open new on correct monitor
    if [ "$CURRENT" != "none" ]; then
        eww close "$CURRENT" 2>/dev/null
    fi
    eww update popup_open="$POPUP"
    if [ "$POPUP" = "calendar-window" ]; then
        ~/.config/eww/scripts/cal-nav.sh reset
    fi
    eww open "$POPUP" --screen "$SCREEN"
    eww open click-catcher-0 --screen 0 2>/dev/null
    eww open click-catcher-1 --screen 1 2>/dev/null
fi
