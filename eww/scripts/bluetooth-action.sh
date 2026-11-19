#!/bin/bash
# Usage: bluetooth-action.sh <connect|disconnect> <MAC> | power <on|off>
source ~/.config/eww/scripts/lib/pending-action.sh
detach_onclick "$@"
shift

ACTION="${1:-}"
ARG="${2:-}"

case "$ACTION" in
    connect|disconnect)
        # Keeps anything but a MAC from reaching bluetoothctl as an option.
        [[ $ARG =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || exit 1
        pending_begin bt_pending "$ARG" bluetooth-window \
            bt_devices="$HOME/.config/eww/scripts/bluetooth-devices.sh" \
            bt_connected="$HOME/.config/eww/scripts/bluetooth-connected.sh"
        ;;
    power)
        [[ $ARG == on || $ARG == off ]] || exit 1
        ;;
    *)
        exit 1
        ;;
esac

case "$ACTION" in
    connect)
        # Without --agent, non-interactive bluetoothctl registers none and no bond is stored.
        if ! timeout 2 bluetoothctl info "$ARG" | grep -q 'Paired: yes'; then
            # A non-pairable adapter pairs without bonding, so the pairing is lost on disconnect.
            timeout 2 bluetoothctl pairable on
            timeout 30 bluetoothctl --agent NoInputNoOutput pair "$ARG" || exit 1
            timeout 2 bluetoothctl info "$ARG" | grep -q 'Paired: yes' || exit 1
            timeout 2 bluetoothctl trust "$ARG"
        fi
        timeout 15 bluetoothctl --agent NoInputNoOutput connect "$ARG"
        ;;
    disconnect)
        timeout 10 bluetoothctl disconnect "$ARG"
        ;;
    power)
        [ "$ARG" = on ] && rfkill unblock bluetooth
        timeout 5 bluetoothctl power "$ARG"
        ;;
esac
