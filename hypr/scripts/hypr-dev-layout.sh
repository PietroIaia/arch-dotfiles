#!/usr/bin/env bash
# Dev layout: lazygit (1/7) | terminal (5/7) | lazydocker (1/7)
# Usage: hypr-dev-layout.sh [project_dir]
#
# Hyprland 0.56 evaluates `hyprctl dispatch <arg>` as Lua (`return
# hl.dispatch(<arg>)`), so legacy forms like `dispatch workspace 4` or
# `dispatch resizeactive -- -914 0` are syntax errors, not dispatches.
# Everything below uses the hl.dsp.* API. Failures land in $LOG rather than
# being swallowed.

PROJECT_DIR="${1:-$HOME}"
LOG="${XDG_RUNTIME_DIR:-/tmp}/hypr-dev-layout.log"
: >"$LOG"

log() { printf '%s %s\n' "$(date +%T)" "$*" >>"$LOG"; }

dispatch() {
  local out
  out=$(hyprctl dispatch "$1" 2>&1)
  [ "$out" = "ok" ] || log "dispatch FAILED: $1 -> $out"
}

# Find first empty workspace (1-10)
TARGET_WS=$(hyprctl workspaces -j | jq '[range(1;11)] - [.[].id] | first // empty')

if [ -z "$TARGET_WS" ]; then
  notify-send "Dev Layout" "No empty workspace available (1-10)"
  exit 1
fi

dispatch "hl.dsp.focus{ workspace = \"$TARGET_WS\" }"
sleep 0.3

# Addresses of this workspace's kitty windows, left to right
kitty_addrs() {
  hyprctl clients -j | jq -r --argjson ws "$TARGET_WS" \
    '[.[] | select(.class == "kitty" and .workspace.id == $ws)]
     | sort_by(.at[0]) | .[].address'
}

# Width of one window, by address
width_of() {
  hyprctl clients -j | jq -r --arg a "$1" \
    '[.[] | select(.address == $a)][0].size[0] // empty'
}

wait_for_kitty_count() {
  local expected=$1 attempts=0
  while [ $attempts -lt 20 ]; do
    local count=$(hyprctl clients -j | jq --argjson ws "$TARGET_WS" \
      '[.[] | select(.class == "kitty" and .workspace.id == $ws)] | length')
    [ "$count" -ge "$expected" ] && return 0
    sleep 0.2
    attempts=$((attempts + 1))
  done
  log "timed out waiting for $expected kitty windows on ws $TARGET_WS"
  return 1
}

# Detect venv
VENV_ACTIVATE=""
for venv in .venv venv; do
  [ -f "$PROJECT_DIR/$venv/bin/activate" ] && VENV_ACTIVATE="$PROJECT_DIR/$venv/bin/activate" && break
done

# Spawn: lazygit | project shell | lazydocker.
# preselect is required for the third window: by then the middle pane is
# taller than it is wide, so dwindle would otherwise split it top/bottom.
kitty -e zsh -c 'lazygit; exec zsh' >/dev/null 2>&1 &
wait_for_kitty_count 1
dispatch 'hl.dsp.layout("preselect r")'

if [ -n "$VENV_ACTIVATE" ]; then
  kitty --directory "$PROJECT_DIR" -e env _VENV_ACTIVATE="$VENV_ACTIVATE" zsh >/dev/null 2>&1 &
else
  kitty --directory "$PROJECT_DIR" >/dev/null 2>&1 &
fi
wait_for_kitty_count 2
dispatch 'hl.dsp.layout("preselect r")'

kitty -e zsh -c 'lazydocker; exec zsh' >/dev/null 2>&1 &
wait_for_kitty_count 3

# Resize to 1:5:1.
# Deltas come from measured widths, not monitor width, so gaps and reserved
# areas can't skew the ratio. Shrinking the left pane hands its freed space
# to the middle/right pair, so the right pane is re-measured before its turn.
#
# The x delta moves the vertical divider in absolute layout direction, NOT
# relative to the targeted window: negative moves it left, positive right.
# So shrinking the LEFT pane needs a negative delta, and shrinking the RIGHT
# pane a positive one.
readarray -t WINS < <(kitty_addrs)

if [ "${#WINS[@]}" -ne 3 ]; then
  log "expected 3 kitty windows, found ${#WINS[@]} - skipping resize"
  notify-send "Dev Layout" "Only ${#WINS[@]}/3 terminals appeared; layout not resized"
  exit 1
fi

W_LEFT=$(width_of "${WINS[0]}")
W_MID=$(width_of "${WINS[1]}")
W_RIGHT=$(width_of "${WINS[2]}")
TARGET=$(( (W_LEFT + W_MID + W_RIGHT) / 7 ))

dispatch "hl.dsp.window.resize{ x = $((TARGET - W_LEFT)), y = 0, relative = true, window = \"address:${WINS[0]}\" }"
sleep 0.2

W_RIGHT=$(width_of "${WINS[2]}")
dispatch "hl.dsp.window.resize{ x = $((W_RIGHT - TARGET)), y = 0, relative = true, window = \"address:${WINS[2]}\" }"
sleep 0.2

dispatch "hl.dsp.focus{ window = \"address:${WINS[1]}\" }"

log "final widths: $(width_of "${WINS[0]}") $(width_of "${WINS[1]}") $(width_of "${WINS[2]}") (target ${TARGET} : $((TARGET*5)) : ${TARGET})"
