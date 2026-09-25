#!/usr/bin/env zsh
# Stop all Docker containers, sync, then power off. Used as upsmon SHUTDOWNCMD.
# DRY_RUN=1 only logs what would happen.
log() { logger -t ups-shutdown -- "$*"; echo "$*"; }
run() { if [[ -n ${DRY_RUN:-} ]]; then log "DRY_RUN: $*"; else "$@"; fi }

log "graceful shutdown starting"

if command -v docker > /dev/null 2>&1; then
  containers=(${(f)"$(docker ps -q 2> /dev/null)"})
  if (( ${#containers} )); then
    log "stopping ${#containers} container(s)"
    run docker stop --time 30 $containers
  else
    log "no running containers"
  fi
fi

run sync
run /sbin/shutdown -h now "UPS battery low: graceful shutdown"
