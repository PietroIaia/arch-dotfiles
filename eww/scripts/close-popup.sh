#!/bin/bash
CURRENT=$(eww get popup_open)
if [ "$CURRENT" != "none" ]; then
    eww close "$CURRENT" 2>/dev/null
    eww update popup_open="none"
fi
eww close click-catcher-0 2>/dev/null
eww close click-catcher-1 2>/dev/null
