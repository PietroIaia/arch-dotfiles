#!/usr/bin/env bash
# SmartRe workspace layout, called by the `activate-smartre-env` zsh function
# (which runs `nvim .` in the calling terminal itself).
#   ws1: the calling terminal (moved there if needed, focused at the end)
#   ws2: claude (5/6) | lazydocker (1/6) at the SmartRe-Hub root
# Usage: smartre-layout.sh [caller_window_address]
#
# ws2 windows start with Repos/SmartRe/.venv active and are tagged with their
# own kitty class (smartre-*), so re-running only opens the missing ones.
# Failures go to $LOG.
#
# Hyprland 0.56+ evaluates `hyprctl dispatch <arg>` as Lua, so all dispatches
# use the hl.dsp.* API.

HUB="$HOME/Mahisoft/SmartRe-Hub"
VENV="$HUB/Repos/SmartRe/.venv"
LOG="${XDG_RUNTIME_DIR:-/tmp}/smartre-layout.log"
CALLER="$1"

# Detach from the calling terminal so it's free immediately.
if [ -z "$_SMARTRE_DETACHED" ]; then
  _SMARTRE_DETACHED=1 setsid "$0" "$@" </dev/null &>/dev/null &
  exit 0
fi

: >"$LOG"
log() { printf '%s %s\n' "$(date +%T)" "$*" >>"$LOG"; }

dispatch() {
  local out
  out=$(hyprctl dispatch "$1" 2>&1)
  [ "$out" = "ok" ] || log "dispatch FAILED: $1 -> $out"
}

# Shared agent from ssh-agent.socket (for sessions started before environment.d had it)
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-$XDG_RUNTIME_DIR/ssh-agent.socket}"

addr_of() {  # address of the window with this class, empty if none
  hyprctl clients -j | jq -r --arg c "$1" '[.[] | select(.class == $c)][0].address // empty'
}

width_of() {
  hyprctl clients -j | jq -r --arg a "$1" '[.[] | select(.address == $a)][0].size[0] // empty'
}

ws_of() {
  hyprctl clients -j | jq -r --arg a "$1" '[.[] | select(.address == $a)][0].workspace.id // empty'
}

wait_for() {  # wait_for <class>: block until it maps, print its address
  local i addr
  for i in $(seq 25); do
    addr=$(addr_of "$1") && [ -n "$addr" ] && { echo "$addr"; return 0; }
    sleep 0.2
  done
  log "timed out waiting for $1"
  return 1
}

# spawn <class> <command>: kitty at the Hub root with the venv active; drops to
# a shell (venv still active) when the program exits.
spawn() {
  local act=""
  [ -f "$VENV/bin/activate" ] && act="source '$VENV/bin/activate';"
  kitty --class "$1" --directory "$HUB" -e bash -c "$act $2; exec zsh" &>/dev/null &
}

[ -d "$HUB" ] || { notify-send "SmartRe" "$HUB not found"; exit 1; }
[ -f "$VENV/bin/activate" ] || log "no venv at $VENV - starting without one"

# ---- ws2: claude | lazydocker (5:1) ----
CLAUDE=$(addr_of smartre-claude)
DOCKER=$(addr_of smartre-lazydocker)

if [ -z "$CLAUDE" ] || [ -z "$DOCKER" ]; then
  dispatch 'hl.dsp.focus{ workspace = "2" }'
  sleep 0.2

  if [ -z "$CLAUDE" ]; then
    spawn smartre-claude claude
    CLAUDE=$(wait_for smartre-claude)
  fi

  if [ -z "$DOCKER" ] && [ -n "$CLAUDE" ]; then
    # Split claude to the right, whatever its current shape.
    dispatch "hl.dsp.focus{ window = \"address:$CLAUDE\" }"
    dispatch 'hl.dsp.layout("preselect r")'
    spawn smartre-lazydocker lazydocker
    DOCKER=$(wait_for smartre-lazydocker)
  fi

  # Resize to 5:1. The x delta moves the divider in absolute direction, so
  # shrinking the RIGHT pane needs a positive delta.
  if [ -n "$CLAUDE" ] && [ -n "$DOCKER" ]; then
    sleep 0.2
    W_C=$(width_of "$CLAUDE"); W_D=$(width_of "$DOCKER")
    TARGET=$(( (W_C + W_D) / 6 ))
    dispatch "hl.dsp.window.resize{ x = $((W_D - TARGET)), y = 0, relative = true, window = \"address:$DOCKER\" }"
    sleep 0.2
    log "ws2 widths: $(width_of "$CLAUDE") : $(width_of "$DOCKER") (target $((TARGET*5)) : $TARGET)"
  fi
fi

# ---- ws1: the calling terminal ----
if [ -n "$CALLER" ]; then
  dispatch "hl.dsp.focus{ window = \"address:$CALLER\" }"
  if [ "$(ws_of "$CALLER")" != "1" ]; then
    dispatch 'hl.dsp.window.move{ workspace = "1" }'
    sleep 0.1
    dispatch "hl.dsp.focus{ window = \"address:$CALLER\" }"
  fi
else
  dispatch 'hl.dsp.focus{ workspace = "1" }'
fi
