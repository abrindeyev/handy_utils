#!/usr/bin/env bash

# Scans the current directory for the metrics.2* files
# Returns filenames that have data points within the timeframe below:
#
# 1st parameter: ftdc_directory
# 2nd parameter: start_date (2025-01-06T20:59:09.458Z)
# 3rd parameter: end_date   (2025-01-06T22:59:09.000Z) - optional

ftdc_dir="$1"
start_date="$2"
end_date="${3:-$start_date}"

if [[ "$OSTYPE" =~ ^darwin ]]; then
  date_bin="$(which gdate)"
else
  date_bin="$(which date)"
fi
[[ -f "$date_bin" ]] || { echo "GNU date can't be found! brew install coreutils if you're using macOS, please!"; exit 1; }

function convert_date_to_ts() {
  local isodate="$1"
  "$date_bin" -d "$isodate" '+%s'
}

start_ts="$(convert_date_to_ts "$start_date")"
end_ts="$(convert_date_to_ts "$end_date")"

find -L "$ftdc_dir" -name metrics.2\* -a -type f | while IFS= read -r line; do
  alex_out="$(alexandria -summary "$line")"
  metrics_start="$(echo "$alex_out" | awk -F': ' '/^start:/ {print $2}')"
  metrics_end="$(echo "$alex_out" | awk -F': ' '/^end:/ {print $2}')"

  metrics_start_ts="$(convert_date_to_ts "$metrics_start")"
  metrics_end_ts="$(convert_date_to_ts "$metrics_end")"

  if [[ $metrics_start_ts -ge $start_ts && $metrics_end_ts -le $end_ts   ]] || \
     [[ $metrics_start_ts -le $end_ts   && $metrics_end_ts -ge $start_ts ]]; then
    echo "$line"
  fi
done
