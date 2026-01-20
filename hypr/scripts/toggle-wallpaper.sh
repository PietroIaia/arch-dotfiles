#!/bin/bash

# Wallpaper paths
WALLPAPER1="$HOME/Pictures/Japan_Purple.jpg"
WALLPAPER2="$HOME/Pictures/Purple_alt.png"
STATE_FILE="$HOME/.config/hypr/.state/.wallpaper_state"

# Check current state
if [ -f "$STATE_FILE" ]; then
    CURRENT=$(cat "$STATE_FILE")
else
    CURRENT="purple"
fi

# Toggle wallpaper
if [ "$CURRENT" = "purple" ]; then
    NEW_WALLPAPER="$WALLPAPER1"
    NEW_STATE="japan"
else
    NEW_WALLPAPER="$WALLPAPER2"
    NEW_STATE="purple"
fi

# Kill existing swaybg instances
pkill swaybg

# Set new wallpaper
swaybg --image "$NEW_WALLPAPER" &

# Save new state
echo "$NEW_STATE" > "$STATE_FILE"
