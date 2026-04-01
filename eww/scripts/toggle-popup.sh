#!/bin/bash
# Usage: toggle-popup.sh <popup-name> <screen-index>
POPUP="$1"
SCREEN="$2"
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
    eww open "$POPUP" --screen "$SCREEN"
    eww open click-catcher-0 --screen 0 2>/dev/null
    eww open click-catcher-1 --screen 1 2>/dev/null
fi
