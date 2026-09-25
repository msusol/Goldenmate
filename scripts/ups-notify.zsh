#!/usr/bin/env zsh
# upsmon NOTIFYCMD: start/stop the battery watcher on ONBATT/ONLINE.
case "$NOTIFYTYPE" in
  ONBATT) systemctl start --no-block ups-battery-watch.service ;;
  ONLINE) systemctl stop --no-block ups-battery-watch.service ;;
esac
