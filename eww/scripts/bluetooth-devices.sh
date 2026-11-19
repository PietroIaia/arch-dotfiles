#!/bin/bash
# Emits a yuck box of nearby (RSSI set), not connected Bluetooth devices for the eww bluetooth popup.
# Discovery dies with its client and BlueZ then clears RSSI, so detached timed scans overlap.

set -u

STAMP=/tmp/eww-bt-last-scan
SCAN_INTERVAL=25

now=$(date +%s)
last=0
[[ -r $STAMP ]] && last=$(<"$STAMP")

if (( now - last >= SCAN_INTERVAL )); then
  echo "$now" > "$STAMP"
  setsid timeout 32 bluetoothctl --timeout 30 scan on </dev/null >/dev/null 2>&1 &
fi

objects=$(timeout 1 busctl --json=short call org.bluez / \
  org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null)

jq -L ~/.config/eww/scripts -r '
  include "bluetooth";
  # yuck strings cannot hold a backslash, and an unescaped "${" is evaluated as an expression.
  def esc: gsub("\\\\"; "∖") | gsub("(?<c>[\"$\\{])"; "\\\(.c)");
  # RSSI -90..-40 dBm mapped onto 0..100%.
  def percent: ((. + 90) * 2) | if . > 100 then 100 elif . < 0 then 0 else . end;
  def row:
    "(connection_item :onclick \"~/.config/eww/scripts/bluetooth-action.sh connect \(.mac)\""
    + " :icon \"\(.icon | icon)\" :secured \"\" :name \"\(.name | esc)\" :detail \"\(.rssi | percent)%\""
    + " :pending \"${bt_pending == '\''\(.mac)'\''}\" :locked false)";

  # An alias equal to the dashed MAC is an anonymous beacon.
  devices
  | map(select((.connected | not) and .rssi != null
               and (.name | ascii_upcase | gsub("-"; ":")) != .mac))
  | sort_by(-.rssi)
  | "(box :orientation \"v\" :space-evenly false "
    + (if length > 0 then map(row) | join(" ")
       else "(label :class \"connection-empty\" :text \"Searching…\" :halign \"start\")" end)
    + ")"
' <<<"${objects:-{\}}"
