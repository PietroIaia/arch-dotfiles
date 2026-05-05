#!/usr/bin/env bash
# Run hyprshot with windows fully opaque, then restore the previous opacity.

set -u

get_opacity() {
    hyprctl getoption "decoration:$1" -j | jq -r '.float'
}

prev_active=$(get_opacity active_opacity)
prev_inactive=$(get_opacity inactive_opacity)

restore() {
    hyprctl keyword decoration:active_opacity "$prev_active" >/dev/null
    hyprctl keyword decoration:inactive_opacity "$prev_inactive" >/dev/null
}
trap restore EXIT INT TERM

hyprctl keyword decoration:active_opacity 1 >/dev/null
hyprctl keyword decoration:inactive_opacity 1 >/dev/null

hyprshot "$@"
