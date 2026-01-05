#!/bin/bash

# Monitor event listener for Hyprland
# Automatically runs monitor-setup.sh when monitors are connected/disconnected

SCRIPT_DIR="$HOME/.config/hypr/scripts"

# Function to handle monitor events
handle_monitor_event() {
    case $1 in
        monitoraddedv2*|monitorremovedv2*)
            echo "Monitor event detected: $1"
            sleep 0.5  # Wait for monitor to stabilize
            "$SCRIPT_DIR/monitor-setup.sh"
            ;;
    esac
}

# Listen to Hyprland socket for events
socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    handle_monitor_event "$line"
done
