#!/bin/bash
# Usage: cal-nav.sh <prev|next|reset>
DIR="$1"
MONTH=$(eww get cal_month)
YEAR=$(eww get cal_year)

case "$DIR" in
  prev)
    MONTH=$((MONTH - 1))
    if [ $MONTH -lt 1 ]; then MONTH=12; YEAR=$((YEAR - 1)); fi
    ;;
  next)
    MONTH=$((MONTH + 1))
    if [ $MONTH -gt 12 ]; then MONTH=1; YEAR=$((YEAR + 1)); fi
    ;;
  reset)
    MONTH=$(date +%-m)
    YEAR=$(date +%Y)
    ;;
esac

eww update cal_month="$MONTH" cal_year="$YEAR"
eww update cal_grid="$(~/.config/eww/scripts/cal-grid.sh)"
