#!/usr/bin/env bash
# Run hyprshot with windows fully opaque, then restore the previous opacity.

set -u

get_opacity() {
    hyprctl getoption "decoration:$1" -j | jq -r '.float'
}

prev_active=$(get_opacity active_opacity)
prev_inactive=$(get_opacity inactive_opacity)

# On a Lua config, `hyprctl keyword` is dead: 0.56 rejects it ("keyword can't
# work with non-legacy parsers. Use eval.") and 0.57 removed it ("unknown
# request"). Either way it fails silently when its output is discarded. So
# probe for a working `eval` (a Lua no-op answers "ok") rather than for a
# specific keyword error message; fall back to keyword on a legacy .conf session.
if [[ $(hyprctl eval "local _ = 1" 2>&1) == ok ]]; then
    lua_parser=1
else
    lua_parser=0
fi

set_opacity() {
    if (( lua_parser )); then
        hyprctl eval "hl.config({ decoration = { active_opacity = $1, inactive_opacity = $2 } })" >/dev/null
    else
        hyprctl keyword decoration:active_opacity "$1" >/dev/null
        hyprctl keyword decoration:inactive_opacity "$2" >/dev/null
    fi
}

restore() {
    set_opacity "$prev_active" "$prev_inactive"
}
trap restore EXIT INT TERM

set_opacity 1 1

hyprshot "$@"
