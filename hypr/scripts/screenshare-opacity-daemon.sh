#!/usr/bin/env bash
# Force window opacity to 1 while any screencast (screen-share) stream is active,
# then restore the previous opacity when sharing stops. Mirrors hyprshot-opaque.sh.
#
# Detection: while a screencast is active, xdg-desktop-portal exposes a PipeWire
# node whose node.name starts with "xdg-desktop-portal" and whose media.class is
# "Video/Source". This covers Slack, Zoom, Meet, Teams, OBS, etc. The node only
# exists for the lifetime of the screencast session, so its presence == sharing.

set -u

LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screenshare-opacity-daemon.lock"
exec 9>"$LOCK"
flock -n 9 || exit 0

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screenshare-opacity-daemon.log"
log() { printf '%s %s\n' "$(date +%H:%M:%S.%3N)" "$*" >>"$LOG"; }
: >"$LOG"
log "daemon start pid=$$"

# Maximum reconcile rate, in milliseconds. While a screencast is active,
# PipeWire emits events sub-millisecond apart in a continuous firehose, so we
# can't gate on "time since last event" — it never exceeds any sensible
# threshold. Instead we rate-limit reconcile itself: as long as ANY events are
# flowing, reconcile fires at most once per RECONCILE_MS, giving bounded
# worst-case latency for state changes regardless of event rate.
RECONCILE_MS=200

# The live config: hyprland.lua since 0.56, with hyprland.conf as the fallback.
HYPR_CONF="$HOME/.config/hypr/hyprland.lua"
[[ -f "$HYPR_CONF" ]] || HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

# The "default" opacity to restore to when a share ends. Read from the on-disk
# config rather than the live runtime value, so a daemon that was killed mid-
# share and restarted doesn't snapshot a polluted "1.0" as the baseline.
# The trailing-comma strip is what makes this work on the Lua config too.
read_conf_opacity() {
    local key=$1
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$HYPR_CONF" \
        | tail -1 \
        | sed -E "s/.*=[[:space:]]*//; s/[[:space:],#].*//"
}

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

is_sharing() {
    pw-dump 2>/dev/null \
        | jq -e 'any(.[]?;
            (.info.props["media.class"]? == "Video/Source")
            and ((.info.props["node.name"]? // "") | startswith("xdg-desktop-portal"))
          )' \
        >/dev/null
}

conf_active=$(read_conf_opacity active_opacity)
conf_inactive=$(read_conf_opacity inactive_opacity)
log "config opacity: active=$conf_active inactive=$conf_inactive"
sharing=0

start_share() {
    set_opacity 1 1
    sharing=1
    log "start_share: opacity -> 1"
}

stop_share() {
    if [[ -n "$conf_active" && -n "$conf_inactive" ]]; then
        set_opacity "$conf_active" "$conf_inactive"
    fi
    sharing=0
    log "stop_share: opacity -> active=$conf_active inactive=$conf_inactive"
}

cleanup() {
    (( sharing )) && stop_share
}
trap cleanup EXIT INT TERM

reconcile() {
    if is_sharing; then
        (( sharing )) || start_share
    else
        (( sharing )) && stop_share
    fi
}

reconcile

last_reconcile_ms=0
pw-mon 2>/dev/null | while IFS= read -r _; do
    # $EPOCHREALTIME is a bash builtin (no fork per event); format is secs<radix>micros.
    secs=${EPOCHREALTIME%[.,]*}
    micros=${EPOCHREALTIME#*[.,]}
    now_ms=$(( secs * 1000 + 10#$micros / 1000 ))
    if (( now_ms - last_reconcile_ms >= RECONCILE_MS )); then
        last_reconcile_ms=$now_ms
        reconcile
    fi
done
log "pw-mon pipeline EXITED"
