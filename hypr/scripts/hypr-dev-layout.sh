#!/usr/bin/env bash
# Dev layout: lazygit (1/7) | terminal (5/7) | lazydocker (1/7)
# Usage: hypr-dev-layout.sh [project_dir]

PROJECT_DIR="${1:-$HOME}"

exec &>/dev/null

# Find first empty workspace (1-10)
TARGET_WS=$(hyprctl workspaces -j | jq '[range(1;11)] - [.[].id] | first // empty')

if [ -z "$TARGET_WS" ]; then
  notify-send "Dev Layout" "No empty workspace available (1-10)"
  exit 1
fi

hyprctl dispatch workspace "$TARGET_WS"
sleep 0.3

wait_for_kitty_count() {
  local expected=$1 attempts=0
  while [ $attempts -lt 20 ]; do
    local count=$(hyprctl clients -j | jq --argjson ws "$TARGET_WS" \
      '[.[] | select(.class == "kitty" and .workspace.id == $ws)] | length')
    [ "$count" -ge "$expected" ] && return 0
    sleep 0.2
    attempts=$((attempts + 1))
  done
  return 1
}

# Detect venv
VENV_ACTIVATE=""
for venv in .venv venv; do
  [ -f "$PROJECT_DIR/$venv/bin/activate" ] && VENV_ACTIVATE="$PROJECT_DIR/$venv/bin/activate" && break
done

# Spawn: lazygit | project shell | lazydocker
kitty -e zsh -c 'lazygit; exec zsh' &
wait_for_kitty_count 1
hyprctl dispatch layoutmsg preselect r

if [ -n "$VENV_ACTIVATE" ]; then
  kitty --directory "$PROJECT_DIR" -e env _VENV_ACTIVATE="$VENV_ACTIVATE" zsh &
else
  kitty --directory "$PROJECT_DIR" &
fi
wait_for_kitty_count 2
hyprctl dispatch layoutmsg preselect r

kitty -e zsh -c 'lazydocker; exec zsh' &
wait_for_kitty_count 3

# Resize to 1:5:1 ratio
readarray -t WINS < <(hyprctl clients -j | jq -r --argjson ws "$TARGET_WS" \
  '[.[] | select(.class == "kitty" and .workspace.id == $ws)] | sort_by(.at[0]) | .[].address')

EFFECTIVE_W=$(hyprctl monitors -j | jq -r \
  '[.[] | select(.focused == true)][0] | "\(.width) \(.scale)"' | awk '{printf "%d", $1 / $2}')
DELTA_LEFT=$(awk "BEGIN {printf \"%d\", $EFFECTIVE_W * 5 / 14}")
DELTA_RIGHT=$(awk "BEGIN {printf \"%d\", $EFFECTIVE_W * 2 / 7}")

hyprctl dispatch focuswindow "address:${WINS[0]}"
sleep 0.1
hyprctl dispatch resizeactive -- -${DELTA_LEFT} 0

hyprctl dispatch focuswindow "address:${WINS[2]}"
sleep 0.1
hyprctl dispatch resizeactive -- ${DELTA_RIGHT} 0

hyprctl dispatch focuswindow "address:${WINS[1]}"
