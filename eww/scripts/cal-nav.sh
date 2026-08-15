#!/bin/bash
# Usage: cal-nav.sh <prev|next|reset>
DIR="$1"

if [ "$DIR" = "reset" ]; then
  # Overwriting both from `date` anyway, so skip reading them back from the
  # daemon. This is the path toggle-popup.sh takes on every calendar open.
  MONTH=$(date +%-m)
  YEAR=$(date +%Y)
else
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
  esac
fi

eww update cal_month="$MONTH" cal_year="$YEAR" \
           cal_grid="$(~/.config/eww/scripts/cal-grid.sh "$MONTH" "$YEAR")"
