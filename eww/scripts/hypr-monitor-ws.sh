#!/usr/bin/env bash
# Emit the active workspace id of the monitor at index $1 whenever it changes.
# Event-driven via Hyprland's socket2 — replaces a 100ms hyprctl poll.

set -u
mon="${1:?monitor index required}"
sock="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

emit() {
  hyprctl monitors -j \
    | jq -r --argjson m "$mon" \
        'to_entries | .[] | select(.key == $m) | .value.activeWorkspace.id // -1'
}

emit
exec socat -U - UNIX-CONNECT:"$sock" 2>/dev/null | while IFS= read -r line; do
  case "${line%%>>*}" in
    workspace|workspacev2|focusedmon|moveworkspace|moveworkspacev2|createworkspace|destroyworkspace|monitoradded|monitorremoved)
      emit
      ;;
  esac
done
