#!/bin/sh
# Reverse scripts/install.sh. Vendor data is left in place deliberately.
set -eu

systemctl disable --now konica206 || true

rm -f /etc/systemd/system/konica206.service
rm -f /etc/udev/rules.d/70-konica206.rules
rm -f /etc/sysusers.d/konica206.conf
rm -rf /var/lib/konica206/bin

systemctl daemon-reload
udevadm control --reload || true

echo "Uninstalled. Vendor data under /var/lib/konica206 was left in place."
