#!/bin/sh
# Reverse scripts/install.sh. Vendor data and the rest of the state dir are
# left in place deliberately.
set -eu

home_dir=${KONICA_HOME:-/var/lib/konica206}

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now konica206 2>/dev/null || true
elif command -v rc-service >/dev/null 2>&1; then
  rc-service konica206 stop 2>/dev/null || true
  rc-update del konica206 default 2>/dev/null || true
fi

rm -f /etc/systemd/system/konica206.service
rm -f /etc/systemd/system/konica206.service.d/10-port.conf
rmdir /etc/systemd/system/konica206.service.d 2>/dev/null || true
rm -f /etc/conf.d/konica206 /etc/init.d/konica206
rm -f /etc/udev/rules.d/70-konica206.rules
rm -f /etc/sysusers.d/konica206.conf
rm -rf "$home_dir/bin" "$home_dir/ppd"

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
fi
udevadm control --reload >/dev/null 2>&1 || true

echo "Uninstalled. Vendor data and spool under $home_dir were left in place."
