#!/usr/bin/env zsh
# Stop Docker (and its containers), sync, then power off. Used as upsmon SHUTDOWNCMD.
# DRY_RUN=1 only logs what would happen.
log() { logger -t ups-shutdown -- "$*"; echo "$*"; }
run() { if [[ -n ${DRY_RUN:-} ]]; then log "DRY_RUN: $*"; else "$@"; fi }

log "graceful shutdown starting"

# Stop the Docker daemon (not `docker stop`): the daemon stops containers itself and
# leaves them eligible for `restart: unless-stopped` at next boot. Containers stopped
# individually with `docker stop` would stay down after the outage.
if systemctl is-active --quiet docker.service; then
  log "stopping docker ($(docker ps -q 2> /dev/null | wc -l) container(s) running)"
  run systemctl stop docker.service docker.socket
else
  log "docker not running"
fi

run sync
run /sbin/shutdown -h now "UPS battery low: graceful shutdown"
