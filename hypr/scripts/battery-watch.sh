#!/bin/bash
# Battery threshold notifications.
# - Notifies once at <=20% (low, urgency=normal).
# - Notifies once at <=10% (critical, urgency=critical).
# - Resets state when charging or above 20%, so the next discharge re-triggers.

BAT=/sys/class/power_supply/BAT0
INTERVAL=30
LAST=ok  # ok | low | critical

while true; do
    if [ -r "$BAT/capacity" ] && [ -r "$BAT/status" ]; then
        cap=$(cat "$BAT/capacity")
        status=$(cat "$BAT/status")

        if [ "$status" = "Discharging" ]; then
            if [ "$cap" -le 10 ] && [ "$LAST" != "critical" ]; then
                notify-send -u critical -i battery-caution \
                    -h string:x-canonical-private-synchronous:battery-watch \
                    "Battery critical" "Only ${cap}% remaining — plug in now."
                LAST=critical
            elif [ "$cap" -le 20 ] && [ "$LAST" = "ok" ]; then
                notify-send -u normal -i battery-low \
                    -h string:x-canonical-private-synchronous:battery-watch \
                    "Battery low" "${cap}% remaining."
                LAST=low
            fi
        else
            if [ "$cap" -gt 20 ] || [ "$status" != "Discharging" ]; then
                LAST=ok
            fi
        fi
    fi
    sleep "$INTERVAL"
done
