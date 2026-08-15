#!/bin/bash

# Open a Vivaldi window and force it tiled.
#
# All Vivaldi windows float by default (see the windowrule block in
# hyprland.conf) because JS pop-ups -- Google login, OAuth, share dialogs --
# are indistinguishable from ordinary browser windows on every property
# Hyprland can match. This script is the escape hatch for the $mainMod+I bind:
# it opens a window and tiles that specific one.
#
# It cannot be done with an exec rule ([tile on] vivaldi): when Vivaldi is
# already running, the new window is created by the existing process, so
# Hyprland's exec token never reaches it and the rule is silently dropped.

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

# Start listening BEFORE launching, so a fast-opening window can't be missed.
exec 3< <(timeout 20 socat -U - UNIX-CONNECT:"$SOCKET" 2>/dev/null)

vivaldi "$@" >/dev/null 2>&1 &

while IFS= read -r -t 20 line <&3; do
    case $line in
        openwindow\>\>*)
            IFS=',' read -r address _workspace class _title <<<"${line#openwindow>>}"
            if [ "$class" = "vivaldi-stable" ]; then
                hyprctl dispatch settiled "address:0x$address" >/dev/null
                break
            fi
            ;;
    esac
done

exec 3<&-
