#!/usr/bin/env zsh
# While the UPS is on battery, poll charge; at/below THRESHOLD, trigger a forced
# shutdown through upsmon (which runs SHUTDOWNCMD). Exits when mains returns.
source /etc/nut/ups-shutdown.env
UPS=${UPS:-ups@localhost}
THRESHOLD=${THRESHOLD:-40}
POLL=${POLL:-10}
log() { logger -t ups-watch -- "$*"; }

log "on battery; watching charge (threshold ${THRESHOLD}%)"
while true; do
  ups_status=$(upsc $UPS ups.status 2> /dev/null) || { log "upsc failed"; sleep $POLL; continue }
  charge=$(upsc $UPS battery.charge 2> /dev/null)
  if [[ $ups_status != *OB* ]]; then
    log "back on mains (status=$ups_status); stopping watch"
    exit 0
  fi
  if [[ -n $charge ]] && (( charge <= THRESHOLD )); then
    log "charge ${charge}% <= ${THRESHOLD}%: forcing shutdown"
    exec /usr/sbin/upsmon -c fsd
  fi
  sleep $POLL
done
