#!/bin/bash
# Usage: cal-grid.sh [month] [year]
# cal-nav.sh already knows the month/year it just computed, so it passes them in
# rather than making us round-trip back to the daemon for values it set itself.
MONTH="${1:-$(eww get cal_month)}"
YEAR="${2:-$(eww get cal_year)}"
TODAY_MONTH=$(date +%-m)
TODAY_YEAR=$(date +%Y)
TODAY_DAY=$(date +%-d)

# First weekday of the month: ISO (1=Mon...7=Sun), convert to 0-based Mon-first offset
FIRST_DOW=$(date -d "${YEAR}-$(printf '%02d' $MONTH)-01" +%u)
FIRST_DOW=$(( FIRST_DOW - 1 ))

# Days in current and previous month
DAYS_IN_MONTH=$(date -d "${YEAR}-$(printf '%02d' $MONTH)-01 +1 month -1 day" +%d)

PREV_MONTH=$(( MONTH - 1 ))
PREV_YEAR=$YEAR
if [ $PREV_MONTH -lt 1 ]; then PREV_MONTH=12; PREV_YEAR=$(( YEAR - 1 )); fi
DAYS_IN_PREV=$(date -d "${PREV_YEAR}-$(printf '%02d' $PREV_MONTH)-01 +1 month -1 day" +%d)

out='(box :orientation "v" :space-evenly false :spacing 2'

# Day-name header row
out+=' (box :orientation "h" :space-evenly true'
for name in Mo Tu We Th Fr Sa Su; do
    out+=" (label :class \"cal-day-name\" :text \"$name\")"
done
out+=')'

# Only as many rows as the month actually needs (ceiling division)
ROWS=$(( (FIRST_DOW + DAYS_IN_MONTH + 6) / 7 ))

for row in $(seq 0 $(( ROWS - 1 ))); do
    out+=' (box :orientation "h" :space-evenly true'
    for col in 0 1 2 3 4 5 6; do
        cell=$(( row * 7 + col ))
        if [ $cell -lt $FIRST_DOW ]; then
            day=$(( DAYS_IN_PREV - FIRST_DOW + cell + 1 ))
            class="cal-day cal-other-month"
        elif [ $(( cell - FIRST_DOW + 1 )) -le $DAYS_IN_MONTH ]; then
            day=$(( cell - FIRST_DOW + 1 ))
            if [ $day -eq $TODAY_DAY ] && [ $MONTH -eq $TODAY_MONTH ] && [ $YEAR -eq $TODAY_YEAR ]; then
                class="cal-day cal-today"
            else
                class="cal-day"
            fi
        else
            day=$(( cell - FIRST_DOW - DAYS_IN_MONTH + 1 ))
            class="cal-day cal-other-month"
        fi
        out+=" (label :class \"$class\" :text \"$day\")"
    done
    out+=')'
done

out+=')'
echo "$out"
