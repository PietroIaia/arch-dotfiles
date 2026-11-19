#!/bin/bash
# Emits a JSON array of connected Bluetooth devices ({mac, name, icon}) for the eww bluetooth popup header.

objects=$(timeout 1 busctl --json=short call org.bluez / \
  org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null)

jq -L ~/.config/eww/scripts -c '
  include "bluetooth";
  devices | map(select(.connected)) | sort_by(.name | ascii_downcase)
  # eww blanks any label whose text holds a backslash.
  | map({mac, name: (.name | gsub("\\\\"; "∖")), icon: (.icon | icon)})
' <<<"${objects:-{\}}"
