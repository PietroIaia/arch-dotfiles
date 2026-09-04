#!/bin/bash

# Open a Vivaldi window and force it tiled.
#
# All Vivaldi windows float by default (see the windowrule block in
# hyprland.lua) because JS pop-ups -- Google login, OAuth, share dialogs --
# are indistinguishable from ordinary browser windows on every property
# Hyprland can match. This script is the escape hatch for the $mainMod+I bind:
# it opens a window and tiles that specific one.
#
# It cannot be done with an exec rule ([tile on] vivaldi): when Vivaldi is
# already running, the new window is created by the existing process, so
# Hyprland's exec token never reaches it and the rule is silently dropped.

# Untile one window by address.
#
# Under a Lua config (0.56+) hyprctl parses its dispatch argument as Lua, so the
# old plain-text "settiled address:0x..." is a syntax error -- and because the
# call used to be silenced, the failure was invisible: the window just stayed
# floating. Try the Lua form first, fall back to the legacy one for the
# hyprland.conf fallback session, and complain to stderr if neither lands.
untile() {
    local addr=$1 out

    out=$(hyprctl dispatch \
        "hl.dsp.window.float({ window = 'address:$addr', action = 'disable' })" 2>&1)
    case $out in
        ok*) return 0 ;;
    esac

    out=$(hyprctl dispatch settiled "address:$addr" 2>&1)
    case $out in
        ok*) return 0 ;;
    esac

    echo "vivaldi-tiled: could not untile $addr: $out" >&2
    return 1
}

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

# Start listening BEFORE launching, so a fast-opening window can't be missed.
exec 3< <(timeout 20 socat -U - UNIX-CONNECT:"$SOCKET" 2>/dev/null)

vivaldi "$@" >/dev/null 2>&1 &

while IFS= read -r -t 20 line <&3; do
    case $line in
        openwindow\>\>*)
            IFS=',' read -r address _workspace class _title <<<"${line#openwindow>>}"
            if [ "$class" = "vivaldi-stable" ]; then
                untile "0x$address"
                break
            fi
            ;;
    esac
done

exec 3<&-
