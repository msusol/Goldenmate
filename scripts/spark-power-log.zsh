#!/usr/bin/env zsh
# Log GPU watts, CPU busy %, load average, and UPS status/charge to a daily CSV.
# The UPS does not report load over USB, so this is a proxy: pair it with readings
# from the UPS front display. Run as a user service (spark-power-log.service).
INTERVAL=${INTERVAL:-10}
DIR=${POWER_LOG_DIR:-$HOME/.local/state/spark-power}
KEEP_DAYS=${KEEP_DAYS:-30}
UPS=${UPS:-goldenmate@localhost}

mkdir -p $DIR

# cumulative jiffies from the first line of /proc/stat
cpu_read() {
  local a b c d e f g h
  read -r _ a b c d e f g h _ < /proc/stat
  cpu_total=$(( a + b + c + d + e + f + g + h ))
  cpu_idle=$(( d + e ))
}

cpu_read
prev_total=$cpu_total
prev_idle=$cpu_idle
current_day=""

while true; do
  sleep $INTERVAL

  day=$(date +%F)
  file=$DIR/spark-power-$day.csv
  if [[ $day != $current_day ]]; then
    current_day=$day
    [[ -s $file ]] || echo "timestamp,gpu_watts,gpu_util_pct,cpu_busy_pct,load1,ups_status,ups_charge" > $file
    find $DIR -name 'spark-power-*.csv' -mtime +$KEEP_DAYS -delete 2> /dev/null
  fi

  cpu_read
  d_total=$(( cpu_total - prev_total ))
  d_idle=$(( cpu_idle - prev_idle ))
  prev_total=$cpu_total
  prev_idle=$cpu_idle
  if (( d_total > 0 )); then
    cpu_busy=$(( 100.0 * (d_total - d_idle) / d_total ))
  else
    cpu_busy=0
  fi

  gpu=(${(s:,:)$(nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader,nounits 2> /dev/null)})
  gpu_w=${${gpu[1]:-}// /}
  gpu_u=${${gpu[2]:-}// /}
  load1=${${(s: :)$(< /proc/loadavg)}[1]}

  ups=(${(f)"$(upsc $UPS 2> /dev/null)"})
  ups_st=${${(M)ups:#ups.status:*}#*: }
  ups_ch=${${(M)ups:#battery.charge:*}#*: }

  printf '%s,%s,%s,%.1f,%s,%s,%s\n' \
    "$(date +%FT%T)" "$gpu_w" "$gpu_u" "$cpu_busy" "$load1" "$ups_st" "$ups_ch" >> $file
done
