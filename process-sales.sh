#!/bin/bash
TODAY=$(date +%F)
LOG="logs/run_$TODAY.log"
ID=0

mkdir -p input result archive errors trash logs   # safe to re-run
[ -s result/report.csv ] || echo "id,date,city,sum" > result/report.csv   # header only once

log() {                              # print AND keep a copy in the log file, one place to change it
  echo "$1" | tee -a "$LOG"
}

log "[$(date +%H:%M)] INFO: job started"

# junk first
for f in input/*.tmp; do
  [ -e "$f" ] || continue          # no .tmp today? skip, don't fail on the literal pattern
  mv "$f" trash/
  log "[$(date +%H:%M)] INFO: moved $(basename "$f") to trash/"
done

process_file() {
  local file="$1"
  local name
  name=$(basename "$file")
  log "[$(date +%H:%M)] INFO: reading input/$name"

  if head -n 1 "$file" | grep -q "unit_price"; then
    local city sum
    city=$(awk -F',' 'NR==2 {print $5}' "$file")
    sum=$(awk -F',' 'NR>1 {total += $3*$4} END {printf "%.2f", total}' "$file")
    ID=$((ID + 1))
    echo "$ID,$TODAY,$city,$sum" >> result/report.csv
    mv "$file" "archive/$(basename "$file" .csv)_$TODAY.csv"
    log "[$(date +%H:%M)] INFO: sales sum $sum"
    log "[$(date +%H:%M)] INFO: archived as $(basename "$file" .csv)_$TODAY.csv"
  else
    mv "$file" errors/
    log "[$(date +%H:%M)] ERROR: missing column 'unit_price' in $name"
  fi
}

for f in input/*.csv; do
  [ -e "$f" ] || continue          # no .csv left today? skip, don't fail on the literal pattern
  process_file "$f"
done

log "[$(date +%H:%M)] INFO: job finished"

