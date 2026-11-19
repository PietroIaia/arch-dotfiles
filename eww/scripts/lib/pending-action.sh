# Sourced by the *-action.sh scripts: show loading dots while a slow connection action runs.

# detach_onclick "$@" — re-exec detached, since eww SIGKILLs onclicks after 200ms; caller then shifts.
detach_onclick() {
    if [ "${1:-}" != "--worker" ]; then
        setsid "$0" --worker "$@" </dev/null >/dev/null 2>&1 &
        exit 0
    fi
}

# pending_begin <var> <key> <window> [<refresh-var>=<script>...]
# Drops the run if <key> is already busy, sets <var>=<key>, and on exit clears it and,
# while <window> is open, refreshes each <refresh-var> from its script; then calls pending_after if defined.
pending_begin() {
    PENDING_VAR=$1 PENDING_KEY=$2 PENDING_WINDOW=$3
    PENDING_REFRESH=("${@:4}")
    exec 9>"${XDG_RUNTIME_DIR:-/tmp}/eww-$PENDING_VAR-${PENDING_KEY:0:64}.lock"
    flock -n 9 || exit 0
    eww update "$PENDING_VAR=$PENDING_KEY"
    trap pending_end EXIT
}

pending_end() {
    # A newer click owns the variable; leave its dots alone.
    [ "$(eww get "$PENDING_VAR")" = "$PENDING_KEY" ] && eww update "$PENDING_VAR="
    if (( ${#PENDING_REFRESH[@]} )) && [ "$(eww get popup_open)" = "$PENDING_WINDOW" ]; then
        local updates=() r
        # 9>&-: list scripts start detached scans that must not inherit the lock.
        for r in "${PENDING_REFRESH[@]}"; do updates+=("${r%%=*}=$("${r#*=}" 9>&-)"); done
        eww update "${updates[@]}"
    fi
    if declare -F pending_after >/dev/null; then pending_after; fi
}
