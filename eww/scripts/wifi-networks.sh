#!/bin/bash
# Emits a yuck box of available wifi networks for the eww network popup.
# Triggers a fresh nmcli rescan at most once per RESCAN_INTERVAL seconds;
# uses NM's cached scan results in between so the poll returns quickly.

set -u

STAMP=/tmp/eww-wifi-last-rescan
RESCAN_INTERVAL=25

now=$(date +%s)
last=0
[[ -r $STAMP ]] && last=$(<"$STAMP")

if (( now - last >= RESCAN_INTERVAL )); then
  rescan=yes
  echo "$now" > "$STAMP"
else
  rescan=no
fi

echo "(box :orientation \"v\" :space-evenly false"

nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan "$rescan" \
  | awk -F: '
      length($1) > 0 {
        if ($2+0 > best[$1]) { best[$1] = $2+0; sec[$1] = $3 }
      }
      END {
        for (s in best) printf "%s:%d:%s\n", s, best[s], sec[s]
      }' \
  | sort -t: -k2,2 -nr \
  | awk -F: '
      {
        ssid = $1; signal = $2; security = $3
        icon = (signal >= 75) ? "󰤨" : (signal >= 50) ? "󰤥" : (signal >= 25) ? "󰤢" : "󰤟"
        lock = (security != "") ? "🔒" : ""
        printf "(box :class \"network-item\" :orientation \"h\" :space-evenly true (button :class \"network-connect\" :onclick \"nmcli device wifi connect %s\" (box :orientation \"h\" :space-evenly false (label :class \"network-icon\" :text \"%s\") (label :class \"network-lock\" :text \"%s\") (label :class \"network-name\" :text \"%s\" :halign \"start\" :hexpand true) (label :class \"network-signal\" :text \"%d%%\"))))", ssid, icon, lock, ssid, signal
      }'

echo ")"
