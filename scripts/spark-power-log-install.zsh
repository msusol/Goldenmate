#!/usr/bin/env zsh
# Install and start the sampler as a systemd user service (no sudo needed;
# linger is already enabled, so it runs without a login session).
set -eu
SRC=${0:A:h}
mkdir -p ~/.config/systemd/user
cp $SRC/spark-power-log.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now spark-power-log.service
sleep 12
systemctl --user --no-pager --lines=0 status spark-power-log.service || true
tail -3 ~/.local/state/spark-power/spark-power-$(date +%F).csv
