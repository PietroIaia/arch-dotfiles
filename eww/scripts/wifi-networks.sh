#!/bin/bash
# Emits a yuck box of available wifi networks for the eww network popup.
#
# Never blocks. eww activates this poll only while network-window is open, so
# the first run after every open is what the popup renders from. A foreground
# `--rescan yes` takes ~5s, which left the list empty for those 5s; instead
# always read NM's cached results (~20ms) and kick the rescan off detached,
# rate-limited to once per RESCAN_INTERVAL. A later poll picks up its results.
#
# SSID is requested last because nmcli terse output escapes ':' inside an SSID
# as '\:'. Last means embedded colons only ever spill into trailing fields,
# which get rejoined and unescaped instead of being mistaken for delimiters.
# Needs gawk for PROCINFO sorted_in.

set -u

STAMP=/tmp/eww-wifi-last-rescan
RESCAN_INTERVAL=25

now=$(date +%s)
last=0
[[ -r $STAMP ]] && last=$(<"$STAMP")

if (( now - last >= RESCAN_INTERVAL )); then
  echo "$now" > "$STAMP"
  setsid nmcli device wifi rescan </dev/null >/dev/null 2>&1 &
fi

# Saved profiles decide whether a secured row opens the password field or connects directly.
mapfile -t uuids < <(nmcli -t -f UUID,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }')
saved=
(( ${#uuids[@]} )) && saved=$(nmcli -t -f 802-11-wireless.ssid connection show "${uuids[@]}" 2>/dev/null)
prompt=$(eww get wifi_prompt 2>/dev/null)
# Random per render: a pasted multi-line password must not be able to end the heredoc.
delim=EWW_PSK_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')

echo "(box :orientation \"v\" :space-evenly false"

nmcli -t -f ACTIVE,SIGNAL,SECURITY,SSID device wifi list --rescan no \
  | LC_ALL=C gawk -i ~/.config/eww/scripts/lib/wifi.awk -F: -v prompt="$prompt" -v delim="$delim" '
      # yuck strings cannot hold a backslash, and an unescaped "${" is evaluated as an expression.
      function esc(s) {
        gsub(/\\/, "∖", s)
        gsub(/["${]/, "\\\\&", s)
        return s
      }
      function by_signal_desc(i1, v1, i2, v2) {
        if (v1 + 0 != v2 + 0) { return (v2 + 0) - (v1 + 0) }
        return (i1 < i2) ? -1 : (i1 > i2)
      }
      ARGIND == 1 {
        if (sub(/^802-11-wireless\.ssid:/, "")) { saved[hex(unescape($0))] = 1 }
        next
      }
      {
        ssid = $4
        for (i = 5; i <= NF; i++) { ssid = ssid ":" $i }
        ssid = unescape(ssid)
        if (ssid == "") { next }
        # An active BSSID means we are already on this SSID. The popup header
        # shows it, so it is not something to offer connecting to.
        if ($1 == "yes") { connected[ssid] = 1 }
        if (!(ssid in best) || $2 + 0 > best[ssid]) {
          best[ssid] = $2 + 0
          sec[ssid] = $3
        }
      }
      END {
        PROCINFO["sorted_in"] = "by_signal_desc"
        # Also while an action runs: its refresh on exit would rebuild the list under an open field.
        locked = "${wifi_prompt != '\'''\'' || wifi_pending != '\'''\''}"
        for (ssid in best) {
          if (ssid in connected) { continue }
          signal = best[ssid]
          icon = (signal >= 75) ? "󰤨" : (signal >= 50) ? "󰤥" : (signal >= 25) ? "󰤢" : "󰤟"
          secured = (sec[ssid] != "") ? "yes" : "no"
          h = hex(ssid)
          # nmcli cannot create 802.1X profiles, so those keep the plain connect.
          action = (secured == "yes" && !(h in saved) && sec[ssid] !~ /802\.1X/) ? "prompt" : "connect"
          row = sprintf("(connection_item :onclick \"~/.config/eww/scripts/wifi-action.sh %s %s\" :icon \"%s\" :secured \"%s\" :name \"%s\" :detail \"%d%%\" :pending \"${wifi_pending == '\''%s'\''}\" :locked \"%s\")", action, h, icon, secured, esc(ssid), signal, h, locked)
          # First, because reopening the window for focus resets the scroll. The quoted heredoc
          # keeps the password literal: eww substitutes {} unescaped into sh -c.
          if (h == prompt) {
            head = sprintf("(box :class \"connection-group prompting\" :orientation \"v\" :space-evenly false %s (connection_prompt :onaccept \"~/.config/eww/scripts/wifi-action.sh password %s <<'\''%s'\''\n{}\n%s\" :oncancel \"~/.config/eww/scripts/wifi-action.sh cancel\" :error wifi_prompt_error))", row, h, delim, delim)
          } else {
            rows = rows row
          }
        }
        printf "%s%s", head, rows
      }' <(printf '%s\n' "$saved") -

echo ")"
