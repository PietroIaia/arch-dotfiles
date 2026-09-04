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

echo "(box :orientation \"v\" :space-evenly false"

nmcli -t -f ACTIVE,SIGNAL,SECURITY,SSID device wifi list --rescan no \
  | gawk -F: '
      function unescape(s,    out, i, c) {
        out = ""
        for (i = 1; i <= length(s); i++) {
          c = substr(s, i, 1)
          if (c == "\\" && i < length(s)) { i++; c = substr(s, i, 1) }
          out = out c
        }
        return out
      }
      function by_signal_desc(i1, v1, i2, v2) {
        if (v1 + 0 != v2 + 0) { return (v2 + 0) - (v1 + 0) }
        return (i1 < i2) ? -1 : (i1 > i2)
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
        for (ssid in best) {
          if (ssid in connected) { continue }
          signal = best[ssid]
          icon = (signal >= 75) ? "󰤨" : (signal >= 50) ? "󰤥" : (signal >= 25) ? "󰤢" : "󰤟"
          lock = (sec[ssid] != "") ? "🔒" : ""
          printf "(box :class \"network-item\" :orientation \"h\" :space-evenly true (button :class \"network-connect\" :onclick \"nmcli device wifi connect %s\" (box :orientation \"h\" :space-evenly false (label :class \"network-icon\" :text \"%s\") (label :class \"network-lock\" :text \"%s\") (label :class \"network-name\" :text \"%s\" :halign \"start\" :hexpand true) (label :class \"network-signal\" :text \"%d%%\"))))", ssid, icon, lock, ssid, signal
        }
      }'

echo ")"
