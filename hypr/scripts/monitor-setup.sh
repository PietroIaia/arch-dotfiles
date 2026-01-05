#!/bin/bash

# Get monitor information (array position, not .id)
HDMI_ID=$(hyprctl monitors -j | jq 'to_entries | .[] | select(.value.name == "HDMI-A-1") | .key')
LAPTOP_ID=$(hyprctl monitors -j | jq 'to_entries | .[] | select(.value.name == "eDP-1") | .key')

# Close all eww bars
eww close-all

# Wait a moment for monitors to stabilize
sleep 0.5

# Determine configuration based on which monitors are connected
if [ -n "$HDMI_ID" ]; then
    echo "HDMI connected - HDMI ID: $HDMI_ID, Laptop ID: $LAPTOP_ID"

    # Both monitors connected
    # We want: HDMI shows workspaces 1-5, Laptop shows workspaces 6-10
    # bar = workspaces 1-5, bar1 = workspaces 6-10

    eww open primary-bar --screen $HDMI_ID   # workspaces 1-5 on monitor 0 (HDMI)
    eww open secondary-bar --screen $LAPTOP_ID  # workspaces 6-10 on monitor 1 (laptop)
else
    echo "HDMI not connected - Laptop ID: $LAPTOP_ID"
    # Only laptop connected - it becomes monitor 0, show workspaces 1-5
    eww open primary-bar --screen $LAPTOP_ID
fi
