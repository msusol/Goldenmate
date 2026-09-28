#!/usr/bin/env zsh
# Phase 1-2: configure NUT for a USB-attached UPS (standalone, localhost only).
# Defaults below (vendorid/productid/desc) match a Goldenmate 1000VA Pro; override
# via UPS_NAME/VENDORID/PRODUCTID/UPS_DESC for other hardware.
# Run with: sudo zsh scripts/ups-nut-setup.zsh
# Idempotent: skips blocks already present; backs up each file once as *.orig.
set -eu

if [[ $EUID -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

UPS=${UPS_NAME:-ups}
VENDORID=${VENDORID:-06da}
PRODUCTID=${PRODUCTID:-ffff}
UPS_DESC=${UPS_DESC:-"Goldenmate 1000VA Pro"}
MON_USER=upsmon
CONF=/etc/nut

backup() { [[ -e "$1.orig" ]] || cp -a "$1" "$1.orig"; }

# nut.conf: standalone mode
backup $CONF/nut.conf
if grep -q '^MODE=' $CONF/nut.conf; then
  sed -i 's/^MODE=.*/MODE=standalone/' $CONF/nut.conf
else
  echo 'MODE=standalone' >> $CONF/nut.conf
fi

# ups.conf: driver block
backup $CONF/ups.conf
if ! grep -q "^\[$UPS\]" $CONF/ups.conf; then
  cat >> $CONF/ups.conf << CONF_EOF

[$UPS]
    driver = usbhid-ups
    port = auto
    vendorid = $VENDORID
    productid = $PRODUCTID
    desc = "$UPS_DESC"
CONF_EOF
fi

# upsd.conf: listen on localhost only
backup $CONF/upsd.conf
if ! grep -q '^LISTEN 127.0.0.1' $CONF/upsd.conf; then
  echo 'LISTEN 127.0.0.1 3493' >> $CONF/upsd.conf
fi

# upsd.users + upsmon.conf: local monitor user (random password)
backup $CONF/upsd.users
backup $CONF/upsmon.conf
if ! grep -q "^\[$MON_USER\]" $CONF/upsd.users; then
  PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
  cat >> $CONF/upsd.users << CONF_EOF

[$MON_USER]
    password = $PASS
    upsmon primary
CONF_EOF
  echo "MONITOR $UPS@localhost 1 $MON_USER $PASS primary" >> $CONF/upsmon.conf
fi

chown root:nut $CONF/*.conf $CONF/upsd.users
chmod 640 $CONF/*.conf $CONF/upsd.users

# reload udev so the nut group can open the USB device, then start services
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --attr-match=idVendor=$VENDORID
systemctl daemon-reload
systemctl restart nut-driver-enumerator.service || true
systemctl enable --now nut-server.service nut-monitor.service
systemctl restart nut-server.service nut-monitor.service

sleep 3
systemctl --no-pager --lines=0 status nut-driver@$UPS nut-server nut-monitor || true
echo "--- upsc $UPS ---"
upsc $UPS 2>&1 | grep -E 'battery\.(charge|runtime|voltage)|ups\.(status|load|model|mfr)|device\.(model|mfr)' || upsc $UPS
