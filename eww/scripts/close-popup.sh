#!/bin/bash
# Usage: close-popup.sh [command...] — the command runs after the popup is closed.
# Detached like toggle-popup.sh; the shared lock stops wifi-action.sh's popup_reopen from reviving a closed popup.
if [ "${1:-}" != "--worker" ]; then
    setsid "$0" --worker "$@" </dev/null >/dev/null 2>&1 &
    exit 0
fi
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/eww-popup-toggle.lock"
flock 9
shift

CURRENT=$(eww get popup_open)
if [ "$CURRENT" != "none" ]; then
    eww close "$CURRENT" 2>/dev/null
    eww update popup_open="none"
fi
eww close click-catcher-0 2>/dev/null
eww close click-catcher-1 2>/dev/null
exec 9>&-
(( $# )) && exec "$@"
